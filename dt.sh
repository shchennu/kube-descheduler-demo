#!/bin/bash

# Set kubeconfig
export KUBECONFIG=~/.kube/config

# Create a new namespace
kubectl create namespace demo-namespace

# Get the name of the first node
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# Apply a deployment in the demo-namespace
cat << EOF > nginx-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: demo-namespace
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 10
  template:
    metadata:
      labels:
        app: nginx
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: nginx
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
      nodeSelector:
        kubernetes.io/hostname: $NODE_NAME
EOF

kubectl apply -f nginx-deployment.yaml

# Sleep to allow pods to be scheduled
sleep 60

# Show initial pod distribution
echo "Initial pod distribution:"
kubectl -n demo-namespace get pods -o jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\t"}{.spec.nodeName}{end}' | sort

# Remove nodeSelector from the deployment to allow Kubernetes to spread the pods across nodes
kubectl patch deployment nginx-deployment -n demo-namespace -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'

# Sleep to allow Kubernetes to start rescheduling pods
sleep 60

# Create descheduler policy
cat << EOF > descheduler-policy.yaml
apiVersion: "descheduler.io/v1alpha1"
kind: "DeschedulerPolicy"
strategies:
  "RemovePodsViolatingTopologySpreadConstraint":
    enabled: true
EOF

# Create ConfigMap for the descheduler policy
kubectl create configmap descheduler-policy --from-file=descheduler-policy.yaml -n kube-system

# Run the descheduler job
cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: descheduler-job
  namespace: kube-system
spec:
  template:
    spec:
      serviceAccountName: descheduler-sa
      containers:
      - name: descheduler
        image: k8s.gcr.io/descheduler/descheduler:v0.22.0
        volumeMounts:
        - mountPath: /policy-dir
          name: policy-volume
        command:
        - "/bin/descheduler"
        - "--policy-config-file"
        - "/policy-dir/policy.yaml"
        - "--v=4"
      restartPolicy: Never
      volumes:
      - name: policy-volume
        configMap:
          name: descheduler-policy
EOF

# Sleep to allow pods to be rescheduled
sleep 60

# Show pod distribution after descheduler run
echo "Pod distribution after descheduler run:"
kubectl -n demo-namespace get pods -o jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\t"}{.spec.nodeName}{end}' | sort

# Cleanup
kubectl delete -f nginx-deployment.yaml
kubectl delete configmap descheduler-policy -n kube-system
kubectl delete job descheduler-job -n kube-system
kubectl delete namespace demo-namespace
