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
apiVersion: "descheduler/v1alpha2"
kind: "DeschedulerPolicy"
profiles:
  - name: ProfileName
    pluginConfig:
    - name: "RemovePodsViolatingTopologySpreadConstraint"
      args:
        constraints:
          - DoNotSchedule
          - ScheduleAnyway
    plugins:
      balance:
        enabled:
          - "RemovePodsViolatingTopologySpreadConstraint"
EOF

# Apply the policy and run the descheduler
kubectl apply -f descheduler-policy.yaml -n kube-system
descheduler --policy-file descheduler-policy.yaml --kubeconfig $KUBECONFIG --v 4

# Sleep to allow pods to be rescheduled
sleep 60

# Show pod distribution after descheduler run
echo "Pod distribution after descheduler run:"
kubectl -n demo-namespace get pods -o jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\t"}{.spec.nodeName}{end}' | sort

