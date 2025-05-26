#!/bin/bash
set -euo pipefail

# --- Configuration Variables ---
EKS_CLUSTER_NAME="demo-sunbirdedAA-eks" # <<< REMEMBER TO CHANGE THIS!

# Determine the absolute path of the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

HELM_CHARTS_ROOT_DIR="${BASE_DIR}/helmcharts"
export HELM_CHARTS_ROOT_DIR=$(realpath "$HELM_CHARTS_ROOT_DIR")

# Determine the environment from the current directory name
environment=$(basename "$(pwd)")

# --- AWS Credential Prompts ---
echo -e "\n--- AWS Credentials Configuration ---"
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  read -rp "Enter your AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
fi
if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  read -rsp "Enter your AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
  echo # Newline after silent input
fi
if [[ -z "${AWS_REGION:-}" ]]; then
  read -rp "Enter your AWS_REGION (e.g., us-east-1): " AWS_REGION
fi

# Export terraform variables from the AWS environment variables
export TF_VAR_aws_access_key_id="$AWS_ACCESS_KEY_ID"
export TF_VAR_aws_secret_access_key="$AWS_SECRET_ACCESS_KEY"
export TF_VAR_aws_region="$AWS_REGION"

echo -e "\nPlease ensure you have updated all the mandatory variables as mentioned in the documentation."
echo "The installation will fail if any of the mandatory variables are missing."

# --- Functions ---

create_tf_backend() {
    echo -e "\n--- Creating Terraform State Backend ---"
    local tf_backend_script="${SCRIPT_DIR}/tf_backend.sh"
    if [[ ! -f "$tf_backend_script" ]]; then
        echo "❌ Error: tf_backend.sh not found at $tf_backend_script."
        exit 1
    fi
    bash "$tf_backend_script"
    echo "✅ Terraform state backend created."
}

backup_configs() {
    timestamp=$(date +%d%m%y_%H%M%S)
    echo -e "\n--- Backing up existing config files ---"

    mkdir -p "$HOME/.kube" "$HOME/.config/rclone"

    if [[ -f "$HOME/.kube/config" ]]; then
        mv "$HOME/.kube/config" "$HOME/.kube/config.$timestamp"
        echo "✅ Backed up $HOME/.kube/config to $HOME/.kube/config.$timestamp"
    else
        echo "⚠️ $HOME/.kube/config not found, skipping backup."
    fi

    if [[ -f "$HOME/.config/rclone/rclone.conf" ]]; then
        mv "$HOME/.config/rclone/rclone.conf" "$HOME/.config/rclone/rclone.conf.$timestamp"
        echo "✅ Backed up $HOME/.config/rclone/rclone.conf to $HOME/.config/rclone/rclone.conf.$timestamp"
    else
        echo "⚠️ $HOME/.config/rclone/rclone.conf not found, skipping backup."
    fi

    export KUBECONFIG="$HOME/.kube/config"
    echo "✅ KUBECONFIG environment variable set to $KUBECONFIG."
}

clear_terragrunt_cache() {
    echo -e "\n--- Clearing Terragrunt Cache Folders ---"
    # Assuming .terragrunt-cache might be in any module under BASE_DIR/terraform
    find "${BASE_DIR}/terraform" -type d -name ".terragrunt-cache" -prune -exec rm -rf {} + || echo "No Terragrunt cache found or failed to delete."
    echo "✅ Terragrunt cache cleared."
}

create_tf_resources() {
    echo -e "\n--- Creating AWS Resources using Terragrunt ---"

    local tf_script="${SCRIPT_DIR}/tf.sh"
    if [[ ! -f "$tf_script" ]]; then
        echo "❌ Error: tf.sh not found at $tf_script. This script is considered mandatory."
        exit 1
    fi
    source "$tf_script"

    # The terragrunt_root_dir is where your terragrunt.hcl file resides.
    # Given your current PWD and where you run the script, it implies
    # that your terragrunt.hcl is in the same directory as install.sh.
    local terragrunt_root_dir="$SCRIPT_DIR"

    if [[ ! -d "$terragrunt_root_dir" ]]; then
        echo "❌ Error: Terragrunt root directory not found at: $terragrunt_root_dir"
        exit 1
    fi

    # Change to the terragrunt root directory to ensure commands run in the correct context
    pushd "$terragrunt_root_dir" || { echo "❌ Cannot change to Terragrunt directory: $terragrunt_root_dir"; exit 1; }

    if [[ ! -f "terragrunt.hcl" ]]; then
        echo "❌ terragrunt.hcl not found in $(pwd). Ensure you are in the correct Terragrunt root module directory."
        popd # Return to original directory before exiting
        exit 1
    fi

    clear_terragrunt_cache

    echo "Running terragrunt init -migrate-state..."
    terragrunt init -migrate-state || { echo "❌ Terragrunt init failed. Review output above."; popd; exit 1; }

    echo "Running terragrunt apply --all -auto-approve --terragrunt-non-interactive..."
    terragrunt apply --all -auto-approve --terragrunt-non-interactive || { echo "❌ Terragrunt apply failed. Review output above."; popd; exit 1; }
    echo "✅ AWS resources created successfully."

    popd # Return to original directory

    echo -e "\n--- Configuring kubectl for EKS Cluster ---"
    if [[ -z "$EKS_CLUSTER_NAME" || "$EKS_CLUSTER_NAME" == "<YOUR_EKS_CLUSTER_NAME>" ]]; then
        echo "❌ Error: EKS_CLUSTER_NAME variable not set or is still a placeholder."
        echo "Please edit install.sh and set EKS_CLUSTER_NAME to your actual EKS cluster name."
        exit 1
    fi

    if ! command -v aws &>/dev/null; then
        echo "❌ Error: AWS CLI not found. Please install AWS CLI to update kubeconfig."
        exit 1
    fi

    echo "Running 'aws eks update-kubeconfig --name \"$EKS_CLUSTER_NAME\" --region \"$AWS_REGION\" --kubeconfig \"$HOME/.kube/config\"'..."
    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$HOME/.kube/config"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to update kubeconfig for EKS cluster: $EKS_CLUSTER_NAME."
        echo "Verify the cluster name, region, and your AWS credentials."
        exit 1
    fi
    echo "✅ Kubeconfig updated successfully for EKS cluster: $EKS_CLUSTER_NAME."

    if [[ -f "$HOME/.kube/config" ]]; then
        chmod 600 "$HOME/.kube/config"
        echo "✅ Set permissions for $HOME/.kube/config"
    else
        echo "❌ Error: $HOME/.kube/config still not found after update-kubeconfig. This is unexpected and indicates a problem."
        exit 1
    fi
}

setup_kubernetes_prerequisites() {
    echo -e "\n--- Ensuring Kubernetes Namespaces and Common ConfigMaps ---"
    kubectl create namespace sunbird 2>/dev/null || echo "Namespace 'sunbird' already exists or created."
    kubectl create namespace velero 2>/dev/null || echo "Namespace 'velero' already exists or created."
    kubectl create configmap keycloak-key -n sunbird 2>/dev/null || echo "ConfigMap 'keycloak-key' in 'sunbird' already exists or created."
    echo "✅ Kubernetes prerequisites ensured."
}

certificate_keys() {
    echo -e "\n--- Generating RSA Keys for Certificate Signing ---"

    # This path is relative to BASE_DIR/terraform/aws
    # So if BASE_DIR is /home/ubuntu/AA_Sunbird_Demo, and environment is 'template'
    # this will correctly point to /home/ubuntu/AA_Sunbird_Demo/terraform/aws/template
    local cert_dir="${BASE_DIR}/terraform/aws/$environment"
    mkdir -p "$cert_dir" || { echo "❌ Failed to create directory: $cert_dir"; exit 1; }

    if [[ -f "$cert_dir/certkey.pem" && -f "$cert_dir/certpubkey.pem" ]]; then
        echo "⚠️ Certificate keys already exist in $cert_dir; skipping generation."
    else
        openssl genrsa -out "$cert_dir/certkey.pem" 2048 || { echo "❌ Failed to generate RSA private key."; exit 1; }
        openssl rsa -in "$cert_dir/certkey.pem" -pubout -out "$cert_dir/certpubkey.pem" || { echo "❌ Failed to generate RSA public key."; exit 1; }
        echo "✅ RSA keys generated in $cert_dir."
    fi

    # Escape newlines for YAML
    CERTPRIVATEKEY=$(cat "$cert_dir/certkey.pem" | tr '\n' '\\n' | sed 's/\\n$//') # Remove trailing newline escape
    CERTPUBLICKEY=$(cat "$cert_dir/certpubkey.pem" | tr '\n' '\\n' | sed 's/\\n$//') # Remove trailing newline escape

    # Alternative with double escape for certain usages (ensure this is needed)
    CERTIFICATESIGNPRKEY=$(cat "$cert_dir/certkey.pem" | tr '\n' '\f' | sed 's/\f/\\\\n/g' | tr '\f' '\n' | sed 's/\\\\n$//')
    CERTIFICATESIGNPUKEY=$(cat "$cert_dir/certpubkey.pem" | tr '\n' '\f' | sed 's/\f/\\\\n/g' | tr '\f' '\n' | sed 's/\\\\n$//')

    local global_values_path="${cert_dir}/global-values.yaml"

    # Check if the file exists, if not, create it with apiVersion
    if [[ ! -f "$global_values_path" ]]; then
        echo "apiVersion: v2" > "$global_values_path"
        echo "Creating new global-values.yaml at $global_values_path."
    fi

    # Use a temporary file and atomically replace to avoid corruption and ensure proper appending
    local temp_global_values="${global_values_path}.tmp"
    if ! grep -q "CERTIFICATE_PRIVATE_KEY:" "$global_values_path"; then
        # Append only if not already present
        cp "$global_values_path" "$temp_global_values"
        {
            echo "  CERTIFICATE_PRIVATE_KEY: \"$CERTPRIVATEKEY\""
            echo "  CERTIFICATE_PUBLIC_KEY: \"$CERTPUBLICKEY\""
            echo "  CERTIFICATESIGN_PRIVATE_KEY: \"$CERTIFICATESIGNPRKEY\""
            echo "  CERTIFICATESIGN_PUBLIC_KEY: \"$CERTIFICATESIGNPUKEY\""
        } >> "$temp_global_values"
        mv "$temp_global_values" "$global_values_path"
        echo "✅ Certificate keys appended to $global_values_path."
    else
        echo "⚠️ Certificate keys already found in $global_values_path; skipping append."
    fi
}

certificate_config() {
    echo -e "\n--- Configuring Certificate Keys in Registry Service ---"

    echo "Waiting for NodeBB deployment to be ready (max 5 minutes)..."
    if ! kubectl rollout status deployment nodebb -n sunbird --timeout=300s; then
        echo "❌ NodeBB deployment not ready within 5 minutes. Cannot configure certificates. Manual intervention might be required."
        return 1
    fi
    echo "✅ NodeBB deployment is ready."

    echo "Updating apt and installing jq on NodeBB pod (this might take a moment)..."
    # Execute commands sequentially with error checks
    kubectl -n sunbird exec deploy/nodebb -- apt update -y || { echo "❌ Failed to apt update on NodeBB pod. Check pod logs."; return 1; }
    kubectl -n sunbird exec deploy/nodebb -- apt install -y jq || { echo "❌ Failed to install jq on NodeBB pod. Check pod logs."; return 1; }
    echo "✅ jq installed on NodeBB pod."

    echo "Checking for existing Certificate RSA public key in Registry Service..."
    # Using `set +e` temporarily to allow `curl` to fail without exiting the script,
    # then check its exit status.
    set +e
    CERTKEY=$(kubectl -n sunbird exec deploy/nodebb -- \
        curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey/search' \
        --header 'Content-Type: application/json' --data-raw '{ "filters": {}}' | jq -r '.[0].value // empty' 2>/dev/null)
    curl_exit_code=$?
    set -e

    if [[ "$curl_exit_code" -ne 0 && "$curl_exit_code" -ne 22 ]]; then # 22 is HTTP error, like 404/500
        echo "⚠️ Warning: \`curl\` command to Registry Service failed with exit code $curl_exit_code. This might indicate the Registry Service is not fully ready or accessible."
        echo "Attempting to proceed with public key injection, but keep an eye on Registry Service logs."
    fi

    if [[ -z "$CERTKEY" ]]; then
        echo "Certificate RSA public key not found. Injecting..."
        local cert_dir="${BASE_DIR}/terraform/aws/$environment"
        local global_values_path="${cert_dir}/global-values.yaml"
        # Extract the key carefully, accounting for potential issues with parsing multi-line YAML values
        # Use awk to reliably get the quoted string
        CERTPUBKEY=$(awk -F'"' '/CERTIFICATE_PUBLIC_KEY:/{print $2}' "$global_values_path")

        if [[ -z "$CERTPUBKEY" ]]; then
            echo "❌ Error: CERTIFICATE_PUBLIC_KEY not found in $global_values_path. Cannot inject public key."
            return 1
        fi

        # Ensure the JSON payload is correctly formed with escaped quotes for the key
        set +e # Temporarily disable exit on error for curl
        kubectl -n sunbird exec deploy/nodebb -- curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' \
            --header 'Content-Type: application/json' --data-raw "{\"value\":\"$CERTPUBKEY\"}"
        curl_inject_exit_code=$?
        set -e
        if [[ "$curl_inject_exit_code" -ne 0 ]]; then
            echo "❌ Failed to inject public key. Curl exited with status $curl_inject_exit_code. Review NodeBB pod logs and Registry Service logs."
            return 1
        fi
        echo "✅ Certificate RSA public key injected."
    else
        echo "✅ Certificate RSA public key already present."
    fi
}

install_component() {
    if ! command -v helm &>/dev/null; then
        echo "❌ Helm not found. Please install Helm before proceeding."
        exit 1
    fi

    local component="$1"
    local chart_path="$HELM_CHARTS_ROOT_DIR/$component"
    echo -e "\n--- Installing/Upgrading component: $component from $chart_path ---"

    if [[ ! -d "$chart_path" ]]; then
        echo "❌ Error: Helm chart directory not found for component '$component' at: $chart_path"
        exit 1
    fi
    if [[ ! -f "$chart_path/values.yaml" ]]; then
        echo "❌ Error: values.yaml not found for component '$component' at: $chart_path/values.yaml"
        exit 1
    fi

    local ed_values_flag=""
    if [[ -f "$chart_path/ed-values.yaml" ]]; then
        ed_values_flag="-f $chart_path/ed-values.yaml"
    fi

    # These paths are now relative to BASE_DIR and then down into terraform/aws/$environment
    local global_values_path="${BASE_DIR}/terraform/aws/$environment/global-values.yaml"
    local global_cloud_values_path="${BASE_DIR}/terraform/aws/$environment/global-cloud-values.yaml"

    if [[ ! -f "$global_values_path" ]]; then
        echo "❌ Error: global-values.yaml not found at: $global_values_path"
        exit 1
    fi
    if [[ ! -f "$global_cloud_values_path" ]]; then
        echo "❌ Error: global-cloud-values.yaml not found at: $global_cloud_values_path"
        exit 1
    fi

    if [[ "$component" == "learnbb" ]]; then
        echo "Processing learnbb specific actions..."
        if kubectl get job keycloak-kids-keys -n sunbird &>/dev/null; then
            echo "Deleting existing job keycloak-kids-keys to ensure clean installation..."
            # Using --wait=false to not block if job is stuck deleting, relies on subsequent Helm install to recreate
            kubectl delete job keycloak-kids-keys -n sunbird --timeout=60s --wait=false || echo "⚠️ Failed to delete keycloak-kids-keys job, might already be gone or stuck."
        fi
        # Ensure certificate keys are generated/present before learnbb is installed
        # This call is idempotent, so it's safe to run again.
        certificate_keys
    fi

    echo "Running helm upgrade --install for $component..."
    helm upgrade --install "$component" "$chart_path" --namespace sunbird \
        -f "$chart_path/values.yaml" $ed_values_flag \
        -f "$global_values_path" \
        -f "$global_cloud_values_path" \
        --timeout 45m --debug --wait --wait-for-jobs || { echo "❌ Helm installation failed for $component. Check logs above for details."; exit 1; }
    echo "✅ Component $component installed/upgraded successfully."
}

install_helm_components() {
    setup_kubernetes_prerequisites # Run this once for all components

    # --- START OF MODIFICATION ---
    # Removed "monitoring" from the list of components to install.
    # You can install it separately later if needed.
    local components=("edbb" "learnbb" "knowledgebb" "obsrvbb" "inquirybb" "additional")
    # --- END OF MODIFICATION ---

    for component in "${components[@]}"; do
        install_component "$component"
    done # This `done` correctly closes the `for` loop
    echo "✅ All specified Helm components installed."
}

post_install_nodebb_plugins() {
    echo -e "\n--- Post-Install: NodeBB Plugin Activation and Rebuild ---"

    echo "Waiting for NodeBB deployment to be ready (max 10 minutes)..."
    if ! kubectl rollout status deployment nodebb -n sunbird --timeout=600s; then
        echo "❌ NodeBB deployment not ready after 600s. Skipping plugin activation. Manual intervention might be required."
        return 1
    fi
    echo "✅ NodeBB deployment is ready."

    echo "Activating NodeBB plugins..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-create-forum || { echo "❌ Failed to activate nodebb-plugin-create-forum. Check NodeBB pod logs."; return 1; }
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-sunbird-oidc || { echo "❌ Failed to activate nodebb-plugin-sunbird-oidc. Check NodeBB pod logs."; return 1; }
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-write-api || { echo "❌ Failed to activate nodebb-plugin-write-api. Check NodeBB pod logs."; return 1; }
    echo "✅ NodeBB plugins activated."

    echo "Rebuilding and restarting NodeBB..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb build || { echo "❌ Failed to build NodeBB. Check NodeBB pod logs."; return 1; }
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb restart || { echo "❌ Failed to restart NodeBB. Check NodeBB pod logs."; return 1; }
    echo "✅ NodeBB rebuilt and restarted."
}

dns_mapping() {
    echo -e "\n--- Verifying DNS Mapping ---"
    local domain_name
    local timeout_seconds=300 # 5 minutes for configmap and IP
    local start_time=$(date +%s)

    echo "Waiting for 'lms-env' configmap to be available and contain 'sunbird_web_url'..."
    while true; do
        if kubectl get cm -n sunbird lms-env -ojsonpath='{.data.sunbird_web_url}' &>/dev/null; then
            domain_name=$(kubectl get cm -n sunbird lms-env -ojsonpath='{.data.sunbird_web_url}')
            if [[ -n "$domain_name" ]]; then
                echo "✅ Found sunbird_web_url: $domain_name"
                break
            fi
        fi
        current_time=$(date +%s)
        if (( current_time - start_time >= timeout_seconds )); then
            echo "❌ Timeout waiting for lms-env configmap or sunbird_web_url."
            return 1
        fi
        echo "Still waiting for lms-env configmap to be available and contain sunbird_web_url..."
        sleep 10
    done

    local public_ip
    start_time=$(date +%s) # Reset timer for IP check
    echo "Waiting for 'nginx-public-ingress' service to get an external IP..."
    while true; do
        public_ip=$(kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [[ -n "$public_ip" ]]; then
            echo "✅ Found public IP for nginx-public-ingress: $public_ip"
            break
        fi
        current_time=$(date +%s)
        if (( current_time - start_time >= timeout_seconds )); then
            echo "❌ Timeout waiting for nginx-public-ingress external IP."
            return 1
        fi
        echo "Still waiting for nginx-public-ingress to get an external IP..."
        sleep 10
    done

    local dns_timeout=$((SECONDS + 1200))   # 20 minutes timeout for DNS propagation
    local check_interval=10

    echo -e "\n--- IMPORTANT: MANUAL DNS STEP REQUIRED ---"
    echo "Add or update your DNS A record for domain \`$domain_name\` to point to IP: \`$public_ip\`"
    echo "We will now wait for this DNS change to propagate."

    echo "Waiting for DNS $domain_name to resolve to $public_ip..."
    while ! nslookup "$domain_name" 2>/dev/null | grep -q "$public_ip"; do
        if (( SECONDS >= dns_timeout )); then
            echo "❌ Timeout reached: DNS entry for $domain_name does not point to $public_ip"
            echo "Please manually configure your DNS A record for $domain_name to point to $public_ip and verify."
            return 1
        fi
        echo "Still waiting for DNS $domain_name to point to $public_ip... (Checking every $check_interval seconds)"
        sleep $check_interval
    done

    echo "✅ DNS mapping for $domain_name is set to $public_ip"
}

check_pod_status() {
    local namespace="sunbird"
    declare -A component_labels
    component_labels=(
        ["monitoring"]="app.kubernetes.io/instance=kube-prometheus-stack,app.kubernetes.io/name=kube-prometheus-stack"
        ["edbb"]="app=edbb" # Assuming older 'app' label if not using modern Helm labels
        ["learnbb"]="app=learnbb"
        ["knowledgebb"]="app=knowledgebb"
        ["obsrvbb"]="app=obsrvbb"
        ["inquirybb"]="app=inquirybb"
        ["additional"]="app=additional" # This one is generic, verify specific app labels in 'additional' if issues arise
    )

    echo -e "\n--- Checking Pod Status in Namespace $namespace ---"
    local overall_success=true

    for component in "${!component_labels[@]}"; do
        local label_selector="${component_labels[$component]}"
        echo -e "\nChecking pod(s) for component: '$component' with label selector: '$label_selector' in namespace $namespace"

        local status_check_succeeded=false

        # Check Deployments
        if kubectl get deployment -l "$label_selector" -n "$namespace" &>/dev/null; then
            echo "  Waiting for deployment(s) for '$component' to be available..."
            if kubectl wait --for=condition=available deployment -l "$label_selector" -n "$namespace" --timeout=300s; then
                echo "  ✅ Deployment(s) for '$component' are available."
                status_check_succeeded=true
            else
                echo "  ❌ Deployment(s) for '$component' are not available after 300 seconds."
                kubectl get deployment -l "$label_selector" -n "$namespace"
                kubectl describe deployment -l "$label_selector" -n "$namespace" | head -n 30
                overall_success=false
            fi
        fi

        # Check StatefulSets
        if kubectl get statefulset -l "$label_selector" -n "$namespace" &>/dev/null; then
            echo "  Waiting for StatefulSet(s) for '$component' to be ready..."
            if kubectl wait --for=condition=ready statefulset -l "$label_selector" -n "$namespace" --timeout=300s; then
                echo "  ✅ StatefulSet(s) for '$component' are ready."
                status_check_succeeded=true
            else
                echo "  ❌ StatefulSet(s) for '$component' are not ready after 300 seconds."
                kubectl get statefulset -l "$label_selector" -n "$namespace"
                kubectl describe statefulset -l "$label_selector" -n "$namespace" | head -n 30
                overall_success=false
            fi
        fi

        # Check DaemonSets
        if kubectl get daemonset -l "$label_selector" -n "$namespace" &>/dev/null; then
            echo "  Waiting for DaemonSet(s) for '$component' to be available..."
            if kubectl wait --for=condition=available daemonset -l "$label_selector" -n "$namespace" --timeout=300s; then
                echo "  ✅ DaemonSet(s) for '$component' are available."
                status_check_succeeded=true
            else
                echo "  ❌ DaemonSet(s) for '$component' are not available after 300 seconds."
                kubectl get daemonset -l "$label_selector" -n "$namespace"
                kubectl describe daemonset -l "$label_selector" -n "$namespace" | head -n 30
                overall_success=false
            fi
        fi

        # Fallback raw pod check if no specific controller found or for jobs/other resources
        if ! "$status_check_succeeded"; then # This condition might need adjustment depending on overall logic.
            echo "  Attempting to check raw pods for '$component' with label selector '$label_selector' (if any exist)..."
            if kubectl get pods -l "$label_selector" -n "$namespace" &>/dev/null; then
                echo "  Waiting for pod(s) for '$component' to be ready..."
                if kubectl wait --for=condition=ready pod -l "$label_selector" -n "$namespace" --timeout=300s; then
                    echo "  ✅ Pod(s) for '$component' are ready."
                else
                    echo "  ❌ Pod(s) for '$component' are not ready after 300 seconds (raw check)."
                    kubectl get pods -l "$label_selector" -n "$namespace"
                    kubectl describe pods -l "$label_selector" -n "$namespace" | head -n 30
                    overall_success=false
                fi
            else
                echo "  ⚠️ No Deployments, StatefulSets, DaemonSets, or raw pods found with label selector '$label_selector' for component '$component'."
                echo "  This might be expected if the component is purely a Job or uses different labels not covered."
            fi
        fi
    done

    if ! "$overall_success"; then
        echo "⚠️ One or more critical components' pods are not in a ready state. Manual inspection recommended."
    else
        echo "✅ All essential pods in namespace $namespace are reported as ready."
    fi
}


# --- Main execution flow ---
main() {
    echo "Starting Sunbird EKS Platform Installation Process..."

    # Ensure necessary tooling is present
    echo -e "\n--- Checking Required Tools ---"
    if ! command -v aws &>/dev/null; then
        echo "❌ AWS CLI not found. Please install it (e.g., 'sudo apt install awscli')."
        exit 1
    fi
    if ! command -v helm &>/dev/null; then
        echo "❌ Helm not found. Please install Helm (https://helm.sh/docs/intro/install/). It is required for Kubernetes deployments."
        exit 1
    fi
    if ! command -v terragrunt &>/dev/null; then
        echo "❌ Terragrunt not found. Please install Terragrunt (https://terragrunt.gruntwork.io/docs/getting-started/install/). It is required for infrastructure provisioning."
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "❌ JQ not found. Please install JQ (e.g., 'sudo apt install jq'). It is required for JSON parsing."
        exit 1
    fi
    if ! command -v openssl &>/dev/null; then
        echo "❌ OpenSSL not found. Please install OpenSSL (e.g., 'sudo apt install openssl'). It is required for certificate key generation."
        exit 1
    fi
    echo "✅ All required tools are present."

    create_tf_backend
    backup_configs
    create_tf_resources # This will now create/update ~/.kube/config

    echo -e "\n--- Verifying Kubernetes Cluster Connectivity ---"
    kubectl cluster-info || { echo "❌ kubectl cluster-info failed after provisioning. Manual debug required."; exit 1; }
    kubectl get nodes || { echo "❌ kubectl get nodes failed after provisioning. Manual debug required."; exit 1; }
    echo "✅ Kubernetes cluster connection verified."

    install_helm_components
    certificate_config # Ensure this runs after NodeBB is potentially ready and accessible
    post_install_nodebb_plugins
    dns_mapping
    check_pod_status

    echo -e "\n🎉 All core installation tasks completed! Your Sunbird platform should now be accessible."
    echo "Please perform any additional post-installation steps as outlined in the documentation."
}

main "$@"
