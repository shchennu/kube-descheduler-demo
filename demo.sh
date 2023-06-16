#!/bin/bash

# Set default values for parameters
SLEEP_DURATION=30
APP_NAME="nginx"
NAMESPACE="default"
CLUSTER_NAME="my-cluster"

# Function to log a step message
log_step() {
  echo "=== $1 ==="
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to install Docker if not already installed
install_docker() {
  log_step "Installing Docker..."
  if ! command_exists docker; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker "$USER"
    sudo systemctl enable docker
    sudo systemctl start docker
    rm get-docker.sh
  else
    echo "Docker is already installed."
  fi
}

# Function to install kubectl if not already installed
install_kubectl() {
  log_step "Installing kubectl..."
  if ! command_exists kubectl; then
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubectl
  else
    echo "kubectl is already installed."
  fi
}

# Function to cleanup Kind cluster and associated resources
cleanup() {
  log_step "Cleaning up..."
  kind delete cluster --name $CLUSTER_NAME
  kubectl delete deployment $APP_NAME -n $NAMESPACE
  kubectl delete configmap descheduler-policy-configmap -n kube-system
  kubectl delete namespace $NAMESPACE
}

# Function to parse script parameters
parse_parameters() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|--sleep)
        shift
        SLEEP_DURATION=$1
        ;;
      -a|--app)
        shift
        APP_NAME=$1
        ;;
      -n|--namespace)
        shift
        NAMESPACE=$1
        ;;
      -c|--cluster)
        shift
        CLUSTER_NAME=$1
        ;;
      *)
        echo "Invalid parameter: $1"
        exit 1
        ;;
    esac
    shift
  done
}

# Install Docker and kubectl if not already installed
install_docker
install_kubectl

# Parse script parameters
parse_parameters "$@"

# Install Kind
log_step "Installing Kind..."
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Create a multi-node cluster using Kind
log_step "Creating Kind cluster ($CLUSTER_NAME)..."
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF

kind create cluster --name $CLUSTER_NAME --config kind-config.yaml

# Set kubeconfig to use the created cluster
export KUBECONFIG="$(kind get kubeconfig-path --name $CLUSTER_NAME)"

# Label nodes to simulate zones
log_step "Labeling nodes..."
kubectl label nodes --all topology.kubernetes.io/zone=zone1

# Create a Deployment with a TopologySpreadConstraint
log_step "Creating $APP_NAME Deployment in namespace $NAMESPACE..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME-deployment
  namespace: $NAMESPACE
spec:
  selector:
    matchLabels:
      app: $APP_NAME
  replicas: 6
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - name: $APP_NAME
        image: nginx:1.14.2
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: "topology.kubernetes.io/zone"
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: $APP_NAME
EOF

# Install Descheduler
log_step "Installing Descheduler..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/descheduler/main/kubernetes-example-policy.yaml

# Create the Descheduler Policy ConfigMap
log_step "Creating Descheduler Policy ConfigMap..."
cat <<EOF > descheduler-policy.yaml
apiVersion: "descheduler/v1alpha2"
kind: "DeschedulerPolicy"
profiles:
  - name: ProfileName
    pluginConfig:
    - name: "RemovePodsViolatingTopologySpreadConstraint"
      args:
        includeSoftConstraints: false
    plugins:
      balance:
        enabled:
          - "RemovePodsViolatingTopologySpreadConstraint"
EOF

kubectl create configmap descheduler-policy-configmap --from-file=descheduler-policy.yaml -n kube-system

# Update Descheduler Configuration
log_step "Updating Descheduler Configuration..."
kubectl edit deployment descheduler -n kube-system

# Wait for Descheduler to take effect
log_step "Waiting for Descheduler..."
sleep $SLEEP_DURATION

# Check Descheduler logs
log_step "Checking Descheduler logs..."
kubectl logs -l app=descheduler -n kube-system

# Cleanup
cleanup
