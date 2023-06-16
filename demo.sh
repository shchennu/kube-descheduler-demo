#!/bin/bash

# Function to print log step
log_step() {
    echo ""
    echo "=== $1 ==="
    echo ""
}

# Function to install Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        log_step "Installing Docker..."
        # Add installation steps for Docker according to your OS and distribution
        # For example, on Ubuntu:
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo usermod -aG docker "$USER"
        log_step "Docker installed successfully."
    else
        log_step "Docker is already installed."
    fi
}

# Function to install kubectl
install_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_step "Installing kubectl..."
        # Add installation steps for kubectl according to your OS and distribution
        # For example, on Ubuntu:
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
        # Add installation steps for Kind according to your OS and distribution
        # For example, on Ubuntu:
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
        # Add installation steps for Kustomize according to your OS and distribution
        # For example, on Linux:
        curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
        sudo mv kustomize /usr/local/bin/
        log_step "Kustomize installed successfully."
    else
        log_step "Kustomize is already installed."
    fi
}

# Function to create a Kind cluster
create_cluster() {
    log_step "Creating Kind cluster ($1)..."
    kind create cluster --name "$1"
    log_step "Kind cluster created successfully."
}

# Function to label the nodes
label_nodes() {
    log_step "Labeling nodes..."
    kubectl label nodes --all topology.kubernetes.io/zone=zone1
    log_step "Nodes labeled successfully."
}

# Function to deploy the Nginx application
deploy_nginx() {
    log_step "Creating Nginx Deployment..."
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: descheduler-demo
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
    log_step "Nginx Deployment created successfully."
}

# Function to install Descheduler
install_descheduler() {
    log_step "Installing Descheduler..."
    kustomize build 'github.com/kubernetes-sigs/descheduler/kubernetes/deployment?ref=v0.26.1' | kubectl apply -f -
    log_step "Descheduler installed successfully."
}

# Function to display Descheduler logs
display_descheduler_logs() {
    log_step "Checking Descheduler logs..."
    kubectl logs -l app=descheduler -n kube-system
}

# Function to cleanup
cleanup() {
    log_step "Cleaning up..."
    kind delete cluster --name "$1"
    log_step "Cleanup completed successfully."
}

# Main function
main() {
    # Parse script arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --cluster-name) CLUSTER_NAME="$2"; shift ;;
            *) log_step "Unknown parameter passed: $1"; exit 1 ;;
        esac
        shift
    done

    # Install prerequisites
    install_docker
    install_kubectl
    install_kind
    install_kustomize

    # Create Kind cluster
    create_cluster "$CLUSTER_NAME"

    # Label nodes
    label_nodes

    # Deploy Nginx
    deploy_nginx

    # Install Descheduler
    install_descheduler

    # Display Descheduler logs
    display_descheduler_logs

    # Cleanup
    cleanup "$CLUSTER_NAME"
}

# Run the main function
main "$@"
