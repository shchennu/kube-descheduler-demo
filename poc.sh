#!/bin/bash

# Function to log step messages
log_step() {
    echo "=== $1 ==="
}

# Function to install kubectl
install_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_step "Installing kubectl..."
        # Add installation steps for kubectl according to your OS and distribution
        log_step "kubectl installed successfully."
    else
        log_step "kubectl is already installed."
    fi
}

# Function to set the cluster context
set_cluster_context() {
    log_step "Setting cluster context to 'dt'..."
    kubectl config use-context dt
    log_step "Cluster context set to 'dt'."
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
    kubectl apply -f kubernetes-descheduler.yaml --namespace "$namespace"
    log_step "Descheduler installed successfully."
}

# Function to wait for a duration
wait_for_duration() {
    log_step "Waiting for $1 seconds..."
    sleep "$1"
}

# Function to check Descheduler logs for evictions
check_descheduler_logs() {
    log_step "Checking Descheduler logs for evictions..."
    kubectl logs -l app=descheduler -n kube-system | grep "Eviction"
    if [ $? -eq 0 ]; then
        log_step "Evictions found in Descheduler logs."
    else
        log_step "No evictions found in Descheduler logs."
    fi
}

# Function to perform cleanup
cleanup() {
    log_step "Cleaning up..."
    kubectl delete deployment nginx-deployment -n "$namespace"
    log_step "Cleanup completed."
}

# Function to print usage
print_usage() {
    echo "Usage: ./demo.sh [--sleep SLEEP_DURATION] [--namespace NAMESPACE]"
    echo ""
    echo "Options:"
    echo "  --sleep        Sleep duration in seconds before checking Descheduler logs (default: 60)"
    echo "  --namespace    Namespace for the application (default: descheduler-demo)"
}

# Function for main script execution
main() {
    # Default values
    sleep_duration=60
    namespace="descheduler-demo"

    # Parse command-line options
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --sleep) sleep_duration="$2"; shift ;;
            --namespace) namespace="$2"; shift ;;
            *) echo "Unknown parameter: $1"; print_usage; exit 1 ;;
        esac
        shift
    done

    log_step "Starting Demo..."

    install_kubectl

    set_cluster_context

    # Check if namespace exists, create it if necessary
    kubectl get namespace "$namespace" &> /dev/null
    if [[ $? -ne 0 ]]; then
        create_namespace "$namespace"
    else
        log_step "Namespace ($namespace) already exists."
    fi

    deploy_nginx

    install_descheduler

    wait_for_duration "$sleep_duration"

    check_descheduler_logs

    cleanup

    log_step "Demo completed."
}

# Run the main script
main "$@"
