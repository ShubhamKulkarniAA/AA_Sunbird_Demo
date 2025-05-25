#!/bin/bash
set -euo pipefail

# --- Global Configuration ---

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
HELM_CHARTS_BASE_DIR="$(realpath "$SCRIPT_DIR/../../../helmcharts")"

# --- Core Functions ---

check_aws_credentials() {
    echo "Checking AWS credentials and region..."
    # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_REGION must be set as environment variables
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" || -z "${AWS_REGION:-}" ]]; then
        echo "❌ AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) or AWS_REGION not found in environment."
        echo "Please export these environment variables before running the script (e.g., export AWS_ACCESS_KEY_ID='AKIA...')."
        exit 1
    fi
    # Export for Terraform/Terragrunt if they don't pick from environment automatically
    export TF_VAR_aws_access_key_id="$AWS_ACCESS_KEY_ID"
    export TF_VAR_aws_secret_access_key="$AWS_SECRET_ACCESS_KEY"
    export TF_VAR_aws_region="$AWS_REGION"
    echo "✅ AWS credentials and region set."
}

create_tf_backend() {
    echo "Creating Terraform state backend..."
    # tf_backend.sh is expected to be in the same directory as install.sh (i.e., SCRIPT_DIR)
    if [[ ! -f tf_backend.sh ]]; then
        echo "❌ Error: tf_backend.sh not found in $(pwd)."
        exit 1
    fi
    bash tf_backend.sh || { echo "❌ Terraform state backend creation failed."; exit 1; }
    echo "✅ Terraform state backend created."
}

backup_configs() {
    local timestamp=$(date +%d%m%y_%H%M%S)
    echo "Backing up existing config files..."
    mkdir -p ~/.kube ~/.config/rclone # Ensure directories exist for backup
    [[ -f ~/.kube/config ]] && mv ~/.kube/config ~/.kube/config."$timestamp" && echo "✅ Backed up ~/.kube/config." || echo "⚠️ ~/.kube/config not found, skipping backup."
    [[ -f ~/.config/rclone/rclone.conf ]] && mv ~/.config/rclone/rclone.conf ~/.config/rclone/rclone.conf."$timestamp" && echo "✅ Backed up ~/.config/rclone/rclone.conf." || echo "⚠️ ~/.config/rclone/rclone.conf not found, skipping backup."
    # Explicitly set KUBECONFIG, though aws eks update-kubeconfig will manage its content
    export KUBECONFIG="$HOME/.kube/config"
}

clear_terragrunt_cache() {
    echo "Clearing Terragrunt cache..."
    # Find and remove .terragrunt-cache directories in the current working directory
    find . -maxdepth 1 -type d -name ".terragrunt-cache" -exec rm -rf {} + || true # Suppress error if not found
    echo "✅ Terragrunt cache cleared."
}

create_tf_resources() {
    echo "Creating AWS resources using Terragrunt..."
    # terragrunt.hcl is expected in the current working directory (which should be SCRIPT_DIR/template)
    if [[ ! -f "terragrunt.hcl" ]]; then
        echo "❌ terragrunt.hcl not found in $(pwd). Ensure script is in the correct Terragrunt root module directory."
        exit 1
    fi

    clear_terragrunt_cache

    echo "Running terragrunt init..."
    # terragrunt init handles `terraform init` internally
    terragrunt init -migrate-state || { echo "❌ Terragrunt init failed."; exit 1; }

    echo "Running terragrunt apply..."
    # --all applies to all modules defined in terragrunt.hcl or included via include blocks
    terragrunt apply --all -auto-approve --terragrunt-non-interactive || { echo "❌ Terragrunt apply failed."; exit 1; }
    echo "✅ AWS resources created."

    echo "Configuring kubectl for EKS cluster..."
    local EKS_CLUSTER_NAME
    # Retrieve the 'eks_cluster_name' directly from the Terragrunt output
    # This relies on `output "eks_cluster_name" { value = aws_eks_cluster.eks.name }` being in your EKS module
    EKS_CLUSTER_NAME=$(terragrunt output -no-color -json eks_cluster_name | jq -r '.')

    if [[ -z "$EKS_CLUSTER_NAME" || "$EKS_CLUSTER_NAME" == "null" ]]; then
        echo "❌ Error: Could not retrieve EKS_CLUSTER_NAME from Terragrunt outputs (expected 'eks_cluster_name' directly)."
        echo "Please ensure 'eks_cluster_name' is correctly exported in your Terraform module and 'terragrunt apply' ran successfully."
        exit 1
    fi
    echo "Identified EKS Cluster Name: $EKS_CLUSTER_NAME"

    # Ensure AWS CLI is installed before attempting to update kubeconfig
    if ! command -v aws &>/dev/null; then
        echo "❌ Error: AWS CLI not found. Please install AWS CLI to update kubeconfig."
        exit 1
    fi

    # Update kubeconfig to connect kubectl to the EKS cluster
    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$HOME/.kube/config" \
        || { echo "❌ Failed to update kubeconfig for EKS cluster: $EKS_CLUSTER_NAME."; exit 1; }
    echo "✅ Kubeconfig updated for EKS cluster: $EKS_CLUSTER_NAME."
    # Set secure permissions for the kubeconfig file
    chmod 600 ~/.kube/config || { echo "❌ Failed to set permissions for ~/.kube/config."; exit 1; }
}

certificate_keys() {
    echo "Creating RSA keys for certificate signing..."
    local cert_dir="$SCRIPT_DIR" # Keys will be created in the same directory as install.sh
    mkdir -p "$cert_dir" || { echo "❌ Failed to create directory: $cert_dir"; exit 1; }

    if [[ -f "$cert_dir/certkey.pem" && -f "$cert_dir/certpubkey.pem" ]]; then
        echo "⚠️ Certificate keys already exist in $cert_dir; skipping generation."
    else
        openssl genrsa -out "$cert_dir/certkey.pem" 2048 || { echo "❌ Failed to generate RSA private key."; exit 1; }
        openssl rsa -in "$cert_dir/certkey.pem" -pubout -out "$cert_dir/certpubkey.pem" || { echo "❌ Failed to generate RSA public key."; exit 1; }
        echo "✅ RSA keys generated in $cert_dir."
    fi

    # Escape newlines for embedding into YAML
    local CERTPRIVATEKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certkey.pem")
    local CERTPUBLICKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certpubkey.pem")
    local CERTIFICATESIGNPRKEY=$(sed ':a;N;$!ba;s/\n/\\\\n/g' "$cert_dir/certkey.pem") # Double escaped for some contexts
    local CERTIFICATESIGNPUKEY=$(sed ':a;N;$!ba;s/\n/\\\\n/g' "$cert_dir/certpubkey.pem") # Double escaped for some contexts

    local global_values_path="$cert_dir/global-values.yaml"
    [[ ! -f "$global_values_path" ]] && echo "apiVersion: v2" > "$global_values_path" # Create if not exists

    # Check if keys are already present in global-values.yaml to prevent duplication
    if ! grep -q "CERTIFICATE_PRIVATE_KEY:" "$global_values_path"; then
        { echo; echo "  CERTIFICATE_PRIVATE_KEY: \"$CERTPRIVATEKEY\""; echo "  CERTIFICATE_PUBLIC_KEY: \"$CERTPUBLICKEY\""; echo "  CERTIFICATESIGN_PRIVATE_KEY: \"$CERTIFICATESIGNPRKEY\""; echo "  CERTIFICATESIGN_PUBLIC_KEY: \"$CERTIFICATESIGNPUKEY\""; } >> "$global_values_path"
        echo "✅ Certificate keys appended to $global_values_path."
    else
        echo "⚠️ Certificate keys already found in $global_values_path; skipping append."
    fi
}

wait_for_app_ready() {
    local deployment_name="$1"
    local namespace="$2"
    local timeout_seconds="$3"
    echo "Waiting for '$deployment_name' deployment in '$namespace' to be ready (timeout: ${timeout_seconds}s)..."
    kubectl rollout status deployment "$deployment_name" -n "$namespace" --timeout="${timeout_seconds}s" || { echo "❌ Deployment $deployment_name not ready."; return 1; }
    echo "✅ Deployment $deployment_name is ready."

    # Special check for NodeBB application responsiveness
    if [[ "$deployment_name" == "nodebb" ]]; then
        echo "Waiting for NodeBB application responsiveness (port 4567)..."
        local start_time=$(date +%s)
        local nodebb_pod=""
        while true; do
            # Get the actual pod name for kubectl exec
            nodebb_pod=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=nodebb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [[ -n "$nodebb_pod" ]] && kubectl exec -n "$namespace" "$nodebb_pod" -- curl -f -s -o /dev/null -w "%{http_code}" http://localhost:4567/api/status | grep -q "200"; then
                echo "✅ NodeBB application responsive."
                break
            fi
            (( $(date +%s) - start_time >= timeout_seconds )) && { echo "❌ Timeout waiting for NodeBB responsiveness."; return 1; }
            sleep 10
        done
    fi
    return 0
}

certificate_config() {
    echo "Configuring Certificate keys in Registry Service..."
    wait_for_app_ready "nodebb" "sunbird" "300" || { echo "❌ NodeBB not ready for certificate config. Aborting certificate configuration."; return 1; }

    # Use deployment name for kubectl exec to simplify, it will pick an available pod
    local nodebb_deployment_selector="deploy/nodebb"
    echo "Updating apt and installing jq on NodeBB pod ($nodebb_deployment_selector)..."
    kubectl -n sunbird exec "$nodebb_deployment_selector" -- apt update -y || { echo "❌ Failed to update apt on NodeBB pod."; return 1; }
    kubectl -n sunbird exec "$nodebb_deployment_selector" -- apt install -y jq || { echo "❌ Failed to install jq on NodeBB pod."; return 1; }

    echo "Checking for existing Certificate RSA public key in Registry Service..."
    local CERTKEY=$(kubectl -n sunbird exec "$nodebb_deployment_selector" -- \
      curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey/search' \
      --header 'Content-Type: application/json' --data-raw '{ "filters": {}}' | jq -r '.[0].value // empty')

    if [[ -z "$CERTKEY" ]]; then
        echo "Public key not found. Injecting..."
        local global_values_path="$SCRIPT_DIR/global-values.yaml" # Reference path relative to script
        local CERTPUBKEY=$(awk -F'"' '/CERTIFICATE_PUBLIC_KEY/{print $2}' "$global_values_path")
        [[ -z "$CERTPUBKEY" ]] && { echo "❌ Error: CERTIFICATE_PUBLIC_KEY not found in $global_values_path."; return 1; }
        kubectl -n sunbird exec "$nodebb_deployment_selector" -- curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' \
            --header 'Content-Type: application/json' --data-raw "{\"value\":\"$CERTPUBKEY\"}" || { echo "❌ Failed to inject public key."; return 1; }
        echo "✅ Public key injected."
    else
        echo "✅ Public key already present."
    fi
}

install_component() {
    local component="$1"
    echo -e "\n--- Installing/Upgrading: $component ---"

    local ed_values_flag=""
    [[ -f "$HELM_CHARTS_BASE_DIR/$component/ed-values.yaml" ]] && ed_values_flag="-f $HELM_CHARTS_BASE_DIR/$component/ed-values.yaml"

    if [[ "$component" == "learnbb" ]]; then
        echo "Processing learnbb-specific actions..."
        # Delete existing job if it exists to allow recreation during helm upgrade
        kubectl get job keycloak-kids-keys -n sunbird &>/dev/null && \
        kubectl delete job keycloak-kids-keys -n sunbird --timeout=60s || true
        # Ensure certificate keys are generated and updated in global-values.yaml
        certificate_keys
    fi

    # Helm upgrade/install command, referencing values files.
    # global-values.yaml and global-cloud-values.yaml are expected to be in SCRIPT_DIR
    helm upgrade --install "$component" "$HELM_CHARTS_BASE_DIR/$component" --namespace sunbird \
        -f "$HELM_CHARTS_BASE_DIR/$component/values.yaml" $ed_values_flag \
        -f "$SCRIPT_DIR/global-values.yaml" \
        -f "$SCRIPT_DIR/global-cloud-values.yaml" \
        --timeout 30m --debug --wait --wait-for-jobs || { echo "❌ Helm installation failed for $component."; exit 1; }
    echo "✅ Component $component installed/upgraded."
}

install_helm_components() {
    # Create necessary namespaces and configmaps if they don't exist
    kubectl create namespace sunbird 2>/dev/null || true
    kubectl create namespace velero 2>/dev/null || true
    kubectl create configmap keycloak-key -n sunbird 2>/dev/null || true

    # Temporarily change directory to HELM_CHARTS_BASE_DIR for helm commands
    local current_dir=$(pwd)
    cd "$HELM_CHARTS_BASE_DIR" || { echo "❌ Cannot navigate to Helm charts directory: $HELM_CHARTS_BASE_DIR"; exit 1; }

    # List of Helm components to install in order
    local components=("monitoring" "edbb" "learnbb" "knowledgebb" "obsrvbb" "inquirybb" "additional")
    for component in "${components[@]}"; do
        install_component "$component"
    done
    echo "✅ All specified Helm components installed."

    # Return to the original directory where the script started
    cd "$current_dir" || { echo "❌ Failed to return to original directory: $current_dir"; exit 1; }
}

post_install_nodebb_plugins() {
    wait_for_app_ready "nodebb" "sunbird" "600" || { echo "❌ NodeBB not ready for plugin activation. Skipping NodeBB plugin configuration."; return 1; }

    echo "Activating NodeBB plugins..."
    local nodebb_pod=$(kubectl get pods -n sunbird -l app.kubernetes.io/name=nodebb -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb activate nodebb-plugin-create-forum || { echo "❌ Failed to activate create-forum plugin."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb activate nodebb-plugin-sunbird-oidc || { echo "❌ Failed to activate sunbird-oidc plugin."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb activate nodebb-plugin-write-api || { echo "❌ Failed to activate write-api plugin."; return 1; }

    echo "Rebuilding and restarting NodeBB to apply plugin changes..."
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb build || { echo "❌ Failed to build NodeBB."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb restart || { echo "❌ Failed to restart NodeBB."; return 1; }
    echo "✅ NodeBB plugins activated and restarted."
}

dns_mapping() {
    echo "Verifying DNS mapping..."
    local domain_name="" public_ip=""
    local timeout_seconds=300 start_time=$(date +%s)

    # Wait for the lms-env configmap to be available and contain sunbird_web_url
    while true; do
        domain_name=$(kubectl get cm -n sunbird lms-env -o jsonpath='{.data.sunbird_web_url}' 2>/dev/null)
        [[ -n "$domain_name" ]] && break # Exit loop if domain_name is found
        (( $(date +%s) - start_time >= timeout_seconds )) && { echo "❌ Timeout for lms-env configmap/sunbird_web_url."; return 1; }
        echo "Waiting for domain name from lms-env configmap (current: $(( $(date +%s) - start_time ))s / ${timeout_seconds}s)..."
        sleep 10
    done
    echo "✅ Found domain name: $domain_name"

    # Wait for the nginx-public-ingress service to get an external IP
    start_time=$(date +%s)
    while true; do
        public_ip=$(kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        [[ -n "$public_ip" ]] && break # Exit loop if public_ip is found
        (( $(date +%s) - start_time >= timeout_seconds )) && { echo "❌ Timeout for nginx-public-ingress external IP."; return 1; }
        echo "Waiting for public IP from nginx-public-ingress service (current: $(( $(date +%s) - start_time ))s / ${timeout_seconds}s)..."
        sleep 10
    done
    echo "✅ Found public IP: $public_ip"

    local dns_propagation_timeout=$((SECONDS + 1200)) # 20 minutes timeout for DNS propagation
    echo "ACTION REQUIRED: Please add/update your DNS A record for $domain_name to point to $public_ip."
    echo "Waiting for DNS $domain_name to resolve to $public_ip... (Max 20 minutes)"
    while ! nslookup "$domain_name" 2>/dev/null | grep -q "$public_ip"; do
        if (( SECONDS >= dns_propagation_timeout )); then
            echo "❌ DNS timeout: $domain_name does not point to $public_ip."
            echo "Please manually configure your DNS A record for $domain_name to point to $public_ip, then verify."
            return 1
        fi
        echo "Still waiting for DNS $domain_name to point to $public_ip... (Checking every 10 seconds, elapsed: $(( SECONDS - (dns_propagation_timeout - 1200) ))s)"
        sleep 10
    done
    echo "✅ DNS mapping for $domain_name set to $public_ip."
}

check_pod_status() {
    echo -e "\nChecking essential pod statuses..."
    local namespace="sunbird"
    # List of components whose pods' readiness will be checked
    local components=("learnbb" "knowledgebb" "nodebb" "obsrvbb" "inquirybb" "edbb" "monitoring" "additional")
    local overall_success=true

    for pod_label in "${components[@]}"; do
        echo "  - Checking pod(s) with label app=$pod_label in namespace $namespace"
        # First wait for deployment to be available, then individual pods to be ready
        if ! kubectl wait --for=condition=available deployment -l app="$pod_label" -n "$namespace" --timeout=300s 2>/dev/null && \
           ! kubectl wait --for=condition=ready pod -l app="$pod_label" -n "$namespace" --timeout=300s; then
            echo "    ❌ Deployment(s) or Pod(s) with app=$pod_label are not ready after 300 seconds."
            kubectl get pods -l app="$pod_label" -n "$namespace" # Show current pod status
            kubectl describe pods -l app="$pod_label" -n "$namespace" | head -n 30 # Show relevant logs
            overall_success=false
        else
            echo "    ✅ Pod(s) with app=$pod_label are ready."
        fi
    done

    if ! "$overall_success"; then
        echo "⚠️ Some critical pods are not ready. Manual inspection of Kubernetes cluster is recommended."
        exit 1 # Exit if not all critical pods are ready
    fi
    echo "✅ All essential pods reported ready."
}

# --- Main Execution Flow ---
main() {
    echo "Starting Sunbird platform installation."

    echo "Checking prerequisite CLI tools..."
    # Check for all required CLI tools
    command -v aws &>/dev/null || { echo "❌ AWS CLI not found. Please install it."; exit 1; }
    command -v helm &>/dev/null || { echo "❌ Helm not found. Please install it."; exit 1; }
    (command -v terraform &>/dev/null && command -v terragrunt &>/dev/null) || { echo "❌ Terraform or Terragrunt not found. Please install both."; exit 1; }
    command -v jq &>/dev/null || { echo "❌ 'jq' not found. Please install 'jq' (e.g., 'sudo apt install jq')."; exit 1; }
    command -v openssl &>/dev/null || { echo "❌ OpenSSL not found. Please install OpenSSL."; exit 1; }
    echo "✅ All prerequisites met."

    check_aws_credentials # Ensure AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION are set

    # Ensure the script is run from or navigates to the expected Terragrunt root module directory.
    # This script is designed to be placed inside `~/AA_Sunbird_Demo/terraform/aws/template`.
    local current_run_dir=$(pwd)
    if [[ $(basename "$current_run_dir") != "template" ]]; then
        echo "Navigating to 'template' directory: $SCRIPT_DIR"
        cd "$SCRIPT_DIR" || { echo "❌ Cannot navigate to $SCRIPT_DIR. Ensure script is run from or moved to the correct location: ~/AA_Sunbird_Demo/terraform/aws/template."; exit 1; }
        echo "Current working directory: $(pwd)"
    fi

    create_tf_backend # Runs tf_backend.sh to set up S3/DynamoDB backend
    # Crucial step: Source tf.sh to load the backend environment variables into the current shell session
    if [[ -f tf.sh ]]; then
        echo "Sourcing tf.sh to load backend environment variables..."
        source tf.sh || { echo "❌ Failed to source tf.sh. Ensure it was generated correctly by tf_backend.sh."; exit 1; }
        echo "✅ Backend environment variables loaded."
    else
        echo "❌ tf.sh not found after backend creation. This is unexpected and crucial for Terragrunt to function."
        exit 1
    fi

    backup_configs    # Backup existing kubeconfig and rclone.conf
    create_tf_resources # Creates AWS resources via Terragrunt and configures kubectl

    # After create_tf_resources, kubectl should now be able to connect to the cluster
    echo "Verifying Kubernetes cluster connectivity after provisioning..."
    kubectl cluster-info || { echo "❌ kubectl cluster-info failed after provisioning. Manual debug required to check cluster health and kubeconfig."; exit 1; }
    kubectl get nodes || { echo "❌ kubectl get nodes failed after provisioning. Manual debug required to check node health."; exit 1; }
    echo "✅ Kubernetes cluster connection verified."

    # Change directory to the Helm charts base directory for Helm deployments
    echo "Navigating to Helm charts directory: $HELM_CHARTS_BASE_DIR"
    cd "$HELM_CHARTS_BASE_DIR" || { echo "❌ Cannot navigate to Helm charts directory: $HELM_CHARTS_BASE_DIR. Check path configuration."; exit 1; }

    install_helm_components
    certificate_config
    post_install_nodebb_plugins
    dns_mapping
    check_pod_status

    echo -e "\n🎉 Sunbird platform installation completed successfully! You should now be able to access your platform via the configured DNS."
}

# Execute the main function with all arguments passed to the script
main "$@"
