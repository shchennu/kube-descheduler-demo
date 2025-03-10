#!/bin/bash

# Function to log step messages
log_step() {
    echo "=== $1 ==="
}

# Function to install Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        log_step "Installing Docker..."
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo systemctl start docker
        sudo systemctl enable docker
        log_step "Docker installed successfully."
    else
        log_step "Docker is already installed."
    fi
}

# Function to install kubectl
install_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_step "Installing kubectl..."
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl
        sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
        echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
        sudo apt-get update
        sudo apt-get install -y kubectl
        log_step "kubectl installed successfully."
    else
        log_step "kubectl is already installed."
    fi
}

# Function to install Kind
install_kind() {
    if ! command -v kind &> /dev/null; then
        log_step "Installing Kind..."
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
        log_step "Kind installed successfully."
    else
        log_step "Kind is already installed."
    fi
}

# Function to install Kustomize
install_kustomize() {
    if ! command -v kustomize &> /dev/null; then
        log_step "Installing Kustomize..."
        curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
        sudo mv kustomize /usr/local/bin/
        log_step "Kustomize installed successfully."
    else
        log_step "Kustomize is already installed."
    fi
}

# Function to create Kind cluster
create_cluster() {
    log_step "Creating Kind cluster ($1)..."
    kind create cluster --name "$1"
    log_step "Kind cluster ($1) created successfully."
}

# Function to label nodes
label_nodes() {
    log_step "Labeling nodes..."
    kubectl label nodes --all topology.kubernetes.io/zone=zone1
    log_step "Nodes labeled successfully."
}

# Function to create namespace
create_namespace() {
    log_step "Creating namespace ($1)..."
    kubectl create namespace "$1"
    log_step "Namespace ($1) created successfully."
}

# Function to deploy Nginx pods
deploy_nginx() {
    log_step "Deploying Nginx pods with topology spread constraint..."
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: "$namespace"
spec:
  replicas: 6
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: "topology.kubernetes.io/zone"
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: nginx
EOF
    log_step "Nginx pods deployed successfully."
}

# Function to install Descheduler
install_descheduler() {
    log_step "Installing Descheduler..."
    kustomize build 'github.com/kubernetes-sigs/descheduler/kubernetes/deployment?ref=v0.26.1' | kubectl apply -f -
    log_step "Descheduler installed successfully."
}

# Function to wait for a duration
wait_for_duration() {
    log_step "Waiting for $1 seconds..."
    sleep "$1"
}

# Function to check Descheduler logs
check_descheduler_logs() {
    log_step "Checking Descheduler logs..."
    kubectl logs -l app=descheduler -n kube-system
    log_step "Descheduler logs checked."
}

# Function to perform cleanup
cleanup() {
    log_step "Cleaning up..."
    kind delete cluster --name "$1"
    log_step "Cleanup completed."
}

# Function to print usage
print_usage() {
    echo "Usage: ./demo.sh [--sleep SLEEP_DURATION] [--app APP_NAME] [--namespace NAMESPACE] [--cluster CLUSTER_NAME]"
    echo ""
    echo "Options:"
    echo "  --sleep        Sleep duration in seconds before checking Descheduler logs (default: 60)"
    echo "  --app          Name of the application (default: descheduler-app)"
    echo "  --namespace    Namespace for the application (default: descheduler-demo)"
    echo "  --cluster      Name of the Kind cluster (default: demo-cluster)"
}

# Function for main script execution
main() {
    # Default values
    sleep_duration=60
    app_name="descheduler-app"
    namespace="descheduler-demo"
    cluster_name="demo-cluster"

    # Parse command-line options
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --sleep) sleep_duration="$2"; shift ;;
            --app) app_name="$2"; shift ;;
            --namespace) namespace="$2"; shift ;;
            --cluster) cluster_name="$2"; shift ;;
            *) echo "Unknown parameter: $1"; print_usage; exit 1 ;;
        esac
        shift
    done

    log_step "Starting Demo..."

    install_docker
    install_kubectl
    install_kind
    install_kustomize

    # Check if namespace exists, create it if necessary
    kubectl get namespace "$namespace" &> /dev/null
    if [[ $? -ne 0 ]]; then
        create_namespace "$namespace"
    else
        log_step "Namespace ($namespace) already exists."
    fi

    # Check if cluster exists, create it if necessary
    kind get clusters | grep "$cluster_name" &> /dev/null
    if [[ $? -ne 0 ]]; then
        create_cluster "$cluster_name"
    else
        log_step "Kind cluster ($cluster_name) already exists."
    fi

    label_nodes

    deploy_nginx

    install_descheduler

    wait_for_duration "$sleep_duration"

    check_descheduler_logs

    cleanup "$cluster_name"

    log_step "Demo completed."
}

# Run the main script
main "$@"
