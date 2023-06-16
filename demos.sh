#!/bin/bash

# Function to log step messages
log_step() {
    echo "=== $1 ==="
}

# Function to install Docker
install_docker() {
    log_step "Checking Docker installation..."
    if ! command -v docker &> /dev/null; then
        log_step "Docker not found. Installing Docker..."
        # Add installation steps for Docker according to your OS and distribution
        log_step "Docker installed successfully."
    else
        log_step "Docker is already installed."
    fi
}

# Function to install kubectl
install_kubectl() {
    log_step "Checking kubectl installation..."
    if ! command -v kubectl &> /dev/null; then
        log_step "kubectl not found. Installing kubectl..."
        # Add installation steps for kubectl according to your OS and distribution
        log_step "kubectl installed successfully."
    else
        log_step "kubectl is already installed."
    fi
}

# Function to install Kind
install_kind() {
    log_step "Checking Kind installation..."
    if ! command -v kind &> /dev/null; then
        log_step "Kind not found. Installing Kind..."
        # Add installation steps for Kind according to your OS and distribution
        log_step "Kind installed successfully."
    else
        log_step "Kind is already installed."
    fi
}

# Function to install Kustomize
install_kustomize() {
    log_step "Checking Kustomize installation..."
    if ! command -v kustomize &> /dev/null; then
        log_step "Kustomize not found. Installing Kustomize..."
        # Add installation steps for Kustomize according to your OS and distribution
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
    kubectl apply -f kubernetes-descheduler.yaml
    log_step "Descheduler installed successfully."
}

# Function to wait for a duration
wait_for_duration() {
    log_step "Waiting for $1 seconds..."
    sleep "$1"
}

# Function to check Descheduler logs and perform verifications
check_descheduler_logs() {
    log_step "Checking Descheduler logs..."

    # Verify policy configuration
    log_step "Verifying policy configuration..."
    policy_config=$(kubectl get configmap descheduler-policy-configmap -n kube-system -o jsonpath='{.data.policy\.yaml}')
    if [[ -z "$policy_config" ]]; then
        log_step "Error: Policy configuration not found."
    else
        log_step "Policy configuration found:"
        log_step "$policy_config"
    fi

    # Check Descheduler deployment logs
    log_step "Checking Descheduler deployment logs..."
    deployment_logs=$(kubectl logs -n kube-system deployment/descheduler)
    if echo "$deployment_logs" | grep -q "error"; then
        log_step "Error: Descheduler deployment logs contain error messages."
    elif echo "$deployment_logs" | grep -q "warning"; then
        log_step "Warning: Descheduler deployment logs contain warning messages."
    else
        log_step "Descheduler deployment logs checked successfully."
    fi

    # Verify pod labels
    log_step "Verifying pod labels..."
    pod_labels=$(kubectl get pods -n "$namespace" --selector=app=nginx -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels}{"\n"}{end}')
    if [[ -z "$pod_labels" ]]; then
        log_step "Error: No pods with label app=nginx found."
    else
        log_step "Pod labels verified:"
        log_step "$pod_labels"
    fi

    # Check cluster size and node utilization
    log_step "Checking cluster size and node utilization..."
    cluster_size=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | wc -l)
    if [[ "$cluster_size" -lt 2 ]]; then
        log_step "Warning: Cluster size is too small. Skipping evictions."
    else
        node_utilization=$(kubectl top nodes)
        log_step "Node utilization:"
        log_step "$node_utilization"
    fi

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
