#!/bin/bash
set -euo pipefail

EKS_CLUSTER_NAME="demo-sunbirdedAA-eks" # <<< REMEMBER TO CHANGE THIS!

# Check if AWS_ACCESS_KEY_ID is set, else prompt
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  read -rp "Enter your AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
fi

# Check if AWS_SECRET_ACCESS_KEY is set, else prompt
if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  read -rsp "Enter your AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
  echo
fi

# Check if AWS_REGION is set, else prompt
if [[ -z "${AWS_REGION:-}" ]]; then
  read -rp "Enter your AWS_REGION (e.g., us-east-1): " AWS_REGION
fi

# Export terraform variables from the AWS environment variables
export TF_VAR_aws_access_key_id="$AWS_ACCESS_KEY_ID"
export TF_VAR_aws_secret_access_key="$AWS_SECRET_ACCESS_KEY"
export TF_VAR_aws_region="$AWS_REGION"

echo -e "\nPlease ensure you have updated all the mandatory variables as mentioned in the documentation."
echo "The installation will fail if any of the mandatory variables are missing."
echo "Press Enter to continue..."
read -r

environment=$(basename "$(pwd)")
# --- Global Variables ---

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
HELM_CHARTS_BASE_DIR="$(realpath "$SCRIPT_DIR/../../../helmcharts")"

# --- Functions ---

# Function to check for necessary AWS environment variables and provide guidance.
check_aws_credentials() {
    echo -e "\nChecking AWS credentials and region..."
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" || -z "${AWS_REGION:-}" ]]; then
        echo "❌ AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) or AWS_REGION not found in environment variables."
        echo "Please ensure you have configured your AWS CLI using 'aws configure' or exported these variables."
        echo "Example: export AWS_ACCESS_KEY_ID=YOUR_KEY_ID"
        echo "Example: export AWS_SECRET_ACCESS_KEY=YOUR_SECRET_KEY"
        echo "Example: export AWS_REGION=your-aws-region"
        exit 1
    fi
    export TF_VAR_aws_access_key_id="$AWS_ACCESS_KEY_ID"
    export TF_VAR_aws_secret_access_key="$AWS_SECRET_ACCESS_KEY"
    export TF_VAR_aws_region="$AWS_REGION"
    echo "✅ AWS credentials and region are set."
}

create_tf_backend() {
    echo "Creating terraform state backend..."
    # Ensure tf_backend.sh exists and is executable
    if [[ ! -f tf_backend.sh ]]; then
        echo "❌ Error: tf_backend.sh not found."
        echo "❌ Error: tf_backend.sh not found in $(pwd). Make sure it exists and is executable."
        exit 1
    fi
    bash tf_backend.sh
    bash tf_backend.sh || { echo "❌ Terraform state backend creation failed."; exit 1; }
    echo "✅ Terraform state backend created."
}

@@ -52,14 +48,14 @@ backup_configs() {
        mv ~/.kube/config ~/.kube/config."$timestamp"
        echo "✅ Backed up ~/.kube/config to ~/.kube/config.$timestamp"
    else
        echo "⚠️  ~/.kube/config not found, skipping backup"
        echo "⚠️ ~/.kube/config not found, skipping backup"
    fi

    if [[ -f ~/.config/rclone/rclone.conf ]]; then
        mv ~/.config/rclone/rclone.conf ~/.config/rclone/rclone.conf."$timestamp"
        echo "✅ Backed up ~/.config/rclone/rclone.conf to ~/.config/rclone/rclone.conf.$timestamp"
    else
        echo "⚠️  ~/.config/rclone/rclone.conf not found, skipping backup"
        echo "⚠️ ~/.config/rclone/rclone.conf not found, skipping backup"
    fi

@@ -68,63 +64,51 @@ backup_configs() {

clear_terragrunt_cache() {
    echo "Clearing Terragrunt cache folders..."
    find . -type d -name ".terragrunt-cache" -exec rm -rf {} + || echo "No Terragrunt cache found or failed to delete"
    # Using -depth 1 for safety to only remove top-level .terragrunt-cache in current context
    find . -depth 1 -type d -name ".terragrunt-cache" -exec rm -rf {} + || echo "No Terragrunt cache found or failed to delete (may not exist)"
    echo "✅ Terragrunt cache cleared."
}

create_tf_resources() {
    # Assuming tf.sh sets up necessary environment for terraform/terragrunt
    if [[ ! -f tf.sh ]]; then
        echo "❌ Error: tf.sh not found. Skipping sourcing."
        # exit 1 # Depending on if tf.sh is mandatory
    else
        source tf.sh
    fi

    echo -e "\nCreating resources on AWS cloud using Terragrunt..."

    local script_dir
    script_dir=$(dirname "${BASH_SOURCE[0]}")
    cd "$script_dir" || { echo "❌ Cannot find script directory"; exit 1; }
    local current_dir
    current_dir=$(pwd) # Store current directory where script is run from

    echo "📁 Current working directory: $(pwd)"
    if [[ ! -f terragrunt.hcl ]]; then
        echo "❌ terragrunt.hcl not found in $(pwd). Ensure you are in the correct Terragrunt root module directory."
    # Ensure we are in the Terraform/Terragrunt root module directory
    # The script should be executed from ~/AA_Sunbird_Demo/terraform/aws/template
    if [[ $(basename "$current_dir") != "template" || ! -f "terragrunt.hcl" ]]; then
        echo "❌ Error: This script expects to be run from the 'template' directory (e.g., ~/AA_Sunbird_Demo/terraform/aws/template)."
        echo "Current directory: $current_dir"
        exit 1
    fi

    clear_terragrunt_cache

    echo "Running terraform init -migrate-state..."
    terraform init -migrate-state || { echo "❌ Terraform init failed."; exit 1; }
    echo "Running terragrunt init -migrate-state..."
    terragrunt init -migrate-state || { echo "❌ Terragrunt init failed."; exit 1; }

    echo "Running terragrunt apply --all -auto-approve --terragrunt-non-interactive..."
    terragrunt apply --all -auto-approve --terragrunt-non-interactive || { echo "❌ Terragrunt apply failed."; exit 1; }
    echo "✅ AWS resources created successfully."

    # --- CRITICAL ADDITION: Update kubeconfig after cluster creation ---
    echo "Attempting to configure kubectl for the newly created EKS cluster..."
    if [[ -z "$EKS_CLUSTER_NAME" || "$EKS_CLUSTER_NAME" == "<YOUR_EKS_CLUSTER_NAME>" ]]; then
        echo "❌ Error: EKS_CLUSTER_NAME variable not set or is still a placeholder."
        echo "Please edit install.sh and set EKS_CLUSTER_NAME to your actual EKS cluster name."
        exit 1
    fi

    # Ensure AWS CLI is installed
    if ! command -v aws &>/dev/null; then
        echo "❌ Error: AWS CLI not found. Please install AWS CLI to update kubeconfig."
    # Dynamically get the EKS cluster name from Terragrunt output
    # This assumes your Terragrunt module exports the EKS cluster name as 'eks_cluster_name'
    local EKS_CLUSTER_NAME
    EKS_CLUSTER_NAME=$(terragrunt output -no-color -json eks_cluster_name | jq -r '.')
    if [[ -z "$EKS_CLUSTER_NAME" || "$EKS_CLUSTER_NAME" == "null" ]]; then # jq outputs "null" if key not found
        echo "❌ Error: Could not retrieve EKS_CLUSTER_NAME from Terragrunt outputs."
        echo "Please ensure your Terragrunt root module (e.g., main.hcl) exports the EKS cluster name as 'eks_cluster_name'."
        exit 1
    fi
    echo "Identified EKS Cluster Name: $EKS_CLUSTER_NAME"

    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$HOME/.kube/config"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to update kubeconfig for EKS cluster: $EKS_CLUSTER_NAME."
        echo "Verify the cluster name, region, and your AWS credentials."
        exit 1
    fi
    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$HOME/.kube/config" \
        || { echo "❌ Failed to update kubeconfig for EKS cluster: $EKS_CLUSTER_NAME. Verify the cluster name, region, and your AWS credentials."; exit 1; }
    echo "✅ Kubeconfig updated successfully for EKS cluster: $EKS_CLUSTER_NAME."
    # --- END OF CRITICAL ADDITION ---

    if [[ -f ~/.kube/config ]]; then
        chmod 600 ~/.kube/config
@@ -138,8 +122,8 @@ create_tf_resources() {
certificate_keys() {
    echo "Creating RSA keys for certificate signing..."

    # Ensure 'environment' is defined or passed properly. It's defined globally in this script.
    local cert_dir="../terraform/aws/$environment"
    local environment=$(basename "$(pwd)") # Get environment (e.g., 'template') from current dir name
    local cert_dir="../terraform/aws/$environment" # Path to where global-values.yaml is
    mkdir -p "$cert_dir" || { echo "❌ Failed to create directory: $cert_dir"; exit 1; }

    # Check if keys already exist to avoid overwriting
@@ -151,11 +135,11 @@ certificate_keys() {
        echo "✅ RSA keys generated in $cert_dir."
    fi

    # Escape newlines for YAML
    # Escape newlines for YAML (single escape for regular YAML value, double for value within a quoted string in YAML)
    CERTPRIVATEKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certkey.pem")
    CERTPUBLICKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certpubkey.pem")

    # Alternative with double escape for certain usages (ensure this is needed)
    # Double escape for keys that might be consumed as strings which are then unescaped (e.g., in Helm values for secrets)
    CERTIFICATESIGNPRKEY=$(sed ':a;N;$!ba;s/\n/\\\\n/g' "$cert_dir/certkey.pem")
    CERTIFICATESIGNPUKEY=$(sed ':a;N;$!ba;s/\n/\\\\n/g' "$cert_dir/certpubkey.pem")

@@ -179,30 +163,71 @@ certificate_keys() {
    fi
}

# Waits for a Kubernetes deployment to be ready, with an optional application-level check.
# Arguments: $1 = deployment name, $2 = namespace, $3 = timeout in seconds
wait_for_app_ready() {
    local deployment_name="$1"
    local namespace="$2"
    local timeout_seconds="$3"

    echo "Waiting for deployment '$deployment_name' in namespace '$namespace' to be ready..."
    kubectl rollout status deployment "$deployment_name" -n "$namespace" --timeout="${timeout_seconds}s" \
        || { echo "❌ Deployment $deployment_name not ready after ${timeout_seconds}s."; return 1; }
    echo "✅ Deployment $deployment_name is ready."

    # Specific application-level check for NodeBB
    if [[ "$deployment_name" == "nodebb" ]]; then
        echo "Waiting for NodeBB application to be fully available (port 4567)..."
        local start_time=$(date +%s)
        local nodebb_pod=""
        while true; do
            nodebb_pod=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=nodebb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [[ -n "$nodebb_pod" ]]; then
                # Check if NodeBB's internal HTTP server is responsive
                if kubectl exec -n "$namespace" "$nodebb_pod" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:4567/api/status | grep -q "200"; then
                    echo "✅ NodeBB application is responsive."
                    break
                fi
            fi
            local current_time=$(date +%s)
            if (( current_time - start_time >= timeout_seconds )); then
                echo "❌ Timeout waiting for NodeBB application to become responsive."
                return 1
            fi
            echo "Still waiting for NodeBB application to become responsive..."
            sleep 10
        done
    fi
    return 0
}


certificate_config() {
    echo "Configuring Certificate keys..."

    echo "Waiting for NodeBB deployment to be ready before configuring certificates..."
    kubectl rollout status deployment nodebb -n sunbird --timeout=300s || { echo "❌ NodeBB deployment not ready."; return 1; }
    # Ensure NodeBB is fully ready before interacting with its API
    wait_for_app_ready "nodebb" "sunbird" "300" || { echo "❌ NodeBB not ready for certificate configuration."; return 1; }

    echo "Updating apt and installing jq on NodeBB pod..."
    kubectl -n sunbird exec deploy/nodebb -- apt update -y || { echo "❌ Failed to update apt on NodeBB."; return 1; }
    kubectl -n sunbird exec deploy/nodebb -- apt install -y jq || { echo "❌ Failed to install jq on NodeBB."; return 1; }
    local nodebb_pod=$(kubectl get pods -n sunbird -l app.kubernetes.io/name=nodebb -o jsonpath='{.items[0].metadata.name}')
    kubectl -n sunbird exec "$nodebb_pod" -- apt update -y || { echo "❌ Failed to update apt on NodeBB."; return 1; }
    kubectl -n sunbird exec "$nodebb_pod" -- apt install -y jq || { echo "❌ Failed to install jq on NodeBB."; return 1; }

    echo "Checking for existing Certificate RSA public key in Registry Service..."
    CERTKEY=$(kubectl -n sunbird exec deploy/nodebb -- \
    CERTKEY=$(kubectl -n sunbird exec "$nodebb_pod" -- \
      curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey/search' \
      --header 'Content-Type: application/json' --data-raw '{ "filters": {}}' | jq -r '.[0].value // empty')

    if [[ -z "$CERTKEY" ]]; then
        echo "Certificate RSA public key not found. Injecting..."
        local environment=$(basename "$(pwd)") # 'template' or similar
        local cert_dir="../terraform/aws/$environment"
        CERTPUBKEY=$(awk -F'"' '/CERTIFICATE_PUBLIC_KEY/{print $2}' "$cert_dir/global-values.yaml")
        if [[ -z "$CERTPUBKEY" ]]; then
            echo "❌ Error: CERTIFICATE_PUBLIC_KEY not found in global-values.yaml."
            return 1
        fi
        kubectl -n sunbird exec deploy/nodebb -- curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' \
        kubectl -n sunbird exec "$nodebb_pod" -- curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' \
            --header 'Content-Type: application/json' --data-raw "{\"value\":\"$CERTPUBKEY\"}" || { echo "❌ Failed to inject public key."; return 1; }
        echo "✅ Certificate RSA public key injected."
    else
@@ -211,62 +236,45 @@ certificate_config() {
}

install_component() {
    if ! command -v helm &>/dev/null; then
        echo "❌ Helm not found. Please install Helm before proceeding."
        exit 1
    fi

    # Ensure namespaces exist
    kubectl create namespace sunbird 2>/dev/null || true
    kubectl create namespace velero 2>/dev/null || true
    kubectl create configmap keycloak-key -n sunbird 2>/dev/null || true # Ensure this is where it's needed

    local cur_dir
    cur_dir=$(pwd)
    # Adjust directory to helmcharts if not already there
    if [[ $(basename "$cur_dir") != "helmcharts" ]]; then
        if [[ -d "../../../helmcharts" ]]; then
            cd ../../../helmcharts || { echo "❌ Cannot navigate to ../../../helmcharts"; exit 1; }
        else
            echo "❌ helmcharts directory not found at ../../../helmcharts. Please run this script from the correct working directory."
            exit 1
        fi
    fi

    local component="$1"
    echo -e "\n--- Installing/Upgrading component: $component ---"

    local ed_values_flag=""
    if [[ -f "$component/ed-values.yaml" ]]; then
        ed_values_flag="-f $component/ed-values.yaml"
    if [[ -f "$HELM_CHARTS_BASE_DIR/$component/ed-values.yaml" ]]; then
        ed_values_flag="-f $HELM_CHARTS_BASE_DIR/$component/ed-values.yaml"
    fi

    local current_tf_env=$(basename "$SCRIPT_DIR") # e.g., 'template'

    if [[ "$component" == "learnbb" ]]; then
        echo "Processing learnbb specific actions..."
        if kubectl get job keycloak-kids-keys -n sunbird &>/dev/null; then
            echo "Deleting existing job keycloak-kids-keys to ensure clean installation..."
            kubectl delete job keycloak-kids-keys -n sunbird --timeout=60s || echo "⚠️ Failed to delete keycloak-kids-keys job, might already be gone or stuck."
        fi

        # Always ensure certificate_keys is called if not already done, for learnbb specifically
        certificate_keys
        certificate_keys # Always ensure certificate_keys is called if not already done, for learnbb specifically
    fi

    echo "Running helm upgrade --install for $component..."
    helm upgrade --install "$component" "$component" --namespace sunbird \
        -f "$component/values.yaml" $ed_values_flag \
        -f "../terraform/aws/$environment/global-values.yaml" \
        -f "../terraform/aws/$environment/global-cloud-values.yaml" \
    helm upgrade --install "$component" "$HELM_CHARTS_BASE_DIR/$component" --namespace sunbird \
        -f "$HELM_CHARTS_BASE_DIR/$component/values.yaml" $ed_values_flag \
        -f "$SCRIPT_DIR/global-values.yaml" \
        -f "$SCRIPT_DIR/global-cloud-values.yaml" \
        --timeout 30m --debug --wait --wait-for-jobs || { echo "❌ Helm installation failed for $component."; exit 1; }
    echo "✅ Component $component installed/upgraded successfully."

    # Return to original directory (important for subsequent component installations if paths are relative)
    cd "$cur_dir" || { echo "❌ Failed to return to original directory: $cur_dir"; exit 1; }
}

install_helm_components() {
    # It's better to ensure these are in relative paths to where the script assumes 'helmcharts' is
    # For now, assuming script runs from a directory where 'helmcharts' is ../../../helmcharts
    # Ensure namespaces exist
    kubectl create namespace sunbird 2>/dev/null || true
    kubectl create namespace velero 2>/dev/null || true
    # This ConfigMap creation should ideally be part of a Helm chart or pre-requisite.
    # If keycloak-key is expected to be present, consider if it's best placed here.
    kubectl create configmap keycloak-key -n sunbird 2>/dev/null || true

    # It's crucial that this script is run from ~/AA_Sunbird_Demo/terraform/aws/template
    # so that $SCRIPT_DIR/global-values.yaml is correct.
    # The HELM_CHARTS_BASE_DIR is absolute, so helm upgrade can find the charts.
    local components=("monitoring" "edbb" "learnbb" "knowledgebb" "obsrvbb" "inquirybb" "additional")
    for component in "${components[@]}"; do
        install_component "$component"
@@ -275,68 +283,70 @@ install_helm_components() {
}

post_install_nodebb_plugins() {
    echo ">> Waiting for NodeBB deployment to be ready..."
    kubectl rollout status deployment nodebb -n sunbird --timeout=600s || { echo "❌ NodeBB deployment not ready after 600s. Skipping plugin activation."; return 1; }
    wait_for_app_ready "nodebb" "sunbird" "600" || { echo "❌ NodeBB not ready for plugin activation. Skipping plugin activation."; return 1; }

    echo ">> Activating NodeBB plugins..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-create-forum || { echo "❌ Failed to activate nodebb-plugin-create-forum."; return 1; }
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-sunbird-oidc || { echo "❌ Failed to activate nodebb-plugin-sunbird-oidc."; return 1; }
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-write-api || { echo "❌ Failed to activate nodebb-plugin-write-api."; return 1; }
    local nodebb_pod=$(kubectl get pods -n sunbird -l app.kubernetes.io/name=nodebb -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb activate nodebb-plugin-create-forum || { echo "❌ Failed to activate nodebb-plugin-create-forum."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb activate nodebb-plugin-sunbird-oidc || { echo "❌ Failed to activate nodebb-plugin-sunbird-oidc."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb activate nodebb-plugin-write-api || { echo "❌ Failed to activate nodebb-plugin-write-api."; return 1; }

    echo ">> Rebuilding and restarting NodeBB..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb build || { echo "❌ Failed to build NodeBB."; return 1; }
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb restart || { echo "❌ Failed to restart NodeBB."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb build || { echo "❌ Failed to build NodeBB."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb restart || { echo "❌ Failed to restart NodeBB."; return 1; }

    echo "✅ NodeBB plugins activated and NodeBB restarted."
}

dns_mapping() {
    echo -e "\nVerifying DNS mapping..."
    local domain_name
    local timeout_seconds=300 # 5 minutes for configmap and service IP
    local start_time=$(date +%s)

    # Wait for cm 'lms-env' to exist and have the data
    timeout_seconds=300
    start_time=$(date +%s)
    echo "Waiting for lms-env configmap to be available and contain sunbird_web_url..."
    while true; do
        if kubectl get cm -n sunbird lms-env &>/dev/null; then
        if kubectl get cm -n sunbird lms-env -o jsonpath='{.data.sunbird_web_url}' &>/dev/null; then
            domain_name=$(kubectl get cm -n sunbird lms-env -ojsonpath='{.data.sunbird_web_url}')
            if [[ -n "$domain_name" ]]; then
                echo "✅ Found domain name: $domain_name"
                break
            fi
        fi
        current_time=$(date +%s)
        local current_time=$(date +%s)
        if (( current_time - start_time >= timeout_seconds )); then
            echo "❌ Timeout waiting for lms-env configmap or sunbird_web_url."
            return 1
        fi
        echo "Waiting for lms-env configmap to be available and contain sunbird_web_url..."
        sleep 10
    done

    local public_ip
    # Wait for service 'nginx-public-ingress' to have an external IP
    start_time=$(date +%s)
    start_time=$(date +%s) # Reset start time for next wait
    echo "Waiting for nginx-public-ingress to get an external IP..."
    while true; do
        public_ip=$(kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [[ -n "$public_ip" ]]; then
            echo "✅ Found public IP for ingress: $public_ip"
            break
        fi
        current_time=$(date +%s)
        local current_time=$(date +%s)
        if (( current_time - start_time >= timeout_seconds )); then
            echo "❌ Timeout waiting for nginx-public-ingress external IP."
            return 1
        fi
        echo "Waiting for nginx-public-ingress to get an external IP..."
        sleep 10
    done

    local timeout=$((SECONDS + 1200))  # 20 minutes timeout for DNS propagation
    local dns_propagation_timeout=$((SECONDS + 1200)) # 20 minutes timeout for DNS propagation
    local check_interval=10

    echo -e "\nAdd or update your DNS A record for domain $domain_name to point to IP: $public_ip"

    echo "Waiting for DNS $domain_name to resolve to $public_ip..."
    while ! nslookup "$domain_name" 2>/dev/null | grep -q "$public_ip"; do
        if (( SECONDS >= timeout )); then
        if (( SECONDS >= dns_propagation_timeout )); then
            echo "❌ Timeout reached: DNS entry for $domain_name does not point to $public_ip"
            echo "Please manually configure your DNS A record for $domain_name to point to $public_ip."
            return 1
@@ -351,15 +361,19 @@ dns_mapping() {
check_pod_status() {
    local namespace="sunbird"
    # Added nodebb to components for status check since it's critical
    # Note: These labels are 'app' based. If charts use 'app.kubernetes.io/name', adjust.
    local components=("learnbb" "knowledgebb" "nodebb" "obsrvbb" "inquirybb" "edbb" "monitoring" "additional")

    echo -e "\n🧪 Checking pod status in namespace $namespace..."
    local overall_success=true
    for pod_label in "${components[@]}"; do
        echo -e "\nChecking pod(s) with label app=$pod_label in namespace $namespace"
        # Using a safer way to wait for pods, ensuring they are available before checking readiness
        if ! kubectl wait --for=condition=available deployment -l app="$pod_label" -n "$namespace" --timeout=300s 2>/dev/null && \
           ! kubectl wait --for=condition=ready pod -l app="$pod_label" -n "$namespace" --timeout=300s; then
        # Wait for deployment to be available, then check pod readiness
        if ! kubectl wait --for=condition=available deployment -l app="$pod_label" -n "$namespace" --timeout=300s 2>/dev/null; then
            echo "❌ Deployment(s) with app=$pod_label are not available after 300 seconds. Pods may not exist or be starting."
            kubectl get pods -l app="$pod_label" -n "$namespace"
            overall_success=false
        elif ! kubectl wait --for=condition=ready pod -l app="$pod_label" -n "$namespace" --timeout=300s; then
            echo "❌ Pod(s) with app=$pod_label are not ready after 300 seconds"
            kubectl get pods -l app="$pod_label" -n "$namespace"
            kubectl describe pods -l app="$pod_label" -n "$namespace" | head -n 30 # Show top of describe for quick debug
@@ -370,39 +384,86 @@ check_pod_status() {
    done

    if ! "$overall_success"; then
        echo "⚠️ Some pods are not in a ready state. Manual inspection recommended."
        exit 1 # Consider exiting if critical pods are not ready
        echo "⚠️ Some critical pods are not in a ready state. Manual inspection recommended."
        exit 1 # Exit if critical pods are not ready
    fi
    echo "✅ All essential pods in namespace $namespace are reported as ready."
}

# --- Main execution flow ---
main() {
    echo "Starting installation process..."
    echo "Starting Sunbird installation process..."

    # Ensure AWS CLI is present for update-kubeconfig later
    # Ensure necessary CLI tools are installed on the host machine
    echo -e "\nChecking prerequisite CLI tools..."
    if ! command -v aws &>/dev/null; then
        echo "❌ AWS CLI not found. Please install it (e.g., 'sudo apt install awscli')."
        exit 1
    fi
    if ! command -v helm &>/dev/null; then
        echo "❌ Helm not found. Please install Helm (https://helm.sh/docs/intro/install/). "
        exit 1
    fi
    if ! command -v terraform &>/dev/null && ! command -v terragrunt &>/dev/null; then
        echo "❌ Neither Terraform nor Terragrunt found. Please install Terragrunt (https://terragrunt.gruntwork.io/docs/getting-started/install/)."
        echo "Terragrunt includes Terraform."
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "❌ 'jq' not found. Please install it (e.g., 'sudo apt install jq')."
        exit 1
    fi
    echo "✅ All prerequisite CLI tools are installed."


    check_aws_credentials # This will exit if credentials aren't set

    # Navigate to the Terraform/Terragrunt root directory before proceeding
    # This is crucial for terragrunt commands to work correctly.
    # The script expects to be executed from ~/AA_Sunbird_Demo/terraform/aws/template
    local current_script_dir=$(pwd)
    if [[ $(basename "$current_script_dir") != "template" ]]; then
        echo "Attempting to navigate to the 'template' directory for Terraform/Terragrunt operations..."
        if [[ -d "$SCRIPT_DIR" ]]; then
            cd "$SCRIPT_DIR" || { echo "❌ Cannot navigate to $SCRIPT_DIR"; exit 1; }
            echo "Moved to: $(pwd)"
        else
            echo "❌ Error: Script not found in expected 'template' directory, and cannot determine the correct path."
            echo "Please run this script from the directory containing 'terragrunt.hcl' for your environment (e.g., '~/AA_Sunbird_Demo/terraform/aws/template')."
            exit 1
        fi
    fi

    create_tf_backend
    backup_configs
    create_tf_resources # This will now create/update ~/.kube/config
    create_tf_resources # This will create/update ~/.kube/config and get EKS_CLUSTER_NAME

    # After create_tf_resources, kubectl should now be able to connect
    echo -e "\nVerifying Kubernetes cluster connectivity after provisioning..."
    kubectl cluster-info || { echo "❌ kubectl cluster-info failed after provisioning. Manual debug required."; exit 1; }
    kubectl get nodes || { echo "❌ kubectl get nodes failed after provisioning. Manual debug required."; exit 1; }
    echo "✅ Kubernetes cluster connection verified."

    # Now navigate to the helmcharts directory for helm operations
    echo "Navigating to Helm charts directory: $HELM_CHARTS_BASE_DIR"
    cd "$HELM_CHARTS_BASE_DIR" || { echo "❌ Cannot navigate to Helm charts directory: $HELM_CHARTS_BASE_DIR"; exit 1; }
    echo "Current working directory: $(pwd)"

    export environment=$(basename "$SCRIPT_DIR")
    echo "Helm environment set to: $environment"

    install_helm_components
    certificate_config
    certificate_config
    post_install_nodebb_plugins
    dns_mapping
    check_pod_status

    echo -e "\n🎉 All tasks completed successfully! Your Sunbird platform should now be accessible."
}

# Call the main function
main "$@"
