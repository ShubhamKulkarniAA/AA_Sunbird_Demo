#!/bin/bash
set -euo pipefail

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

create_tf_backend() {
    echo "Creating terraform state backend..."
    # Ensure tf_backend.sh exists and is executable
    if [[ ! -f tf_backend.sh ]]; then
        echo "❌ Error: tf_backend.sh not found."
        exit 1
    fi
    bash tf_backend.sh
    echo "✅ Terraform state backend created."
}

backup_configs() {
    timestamp=$(date +%d%m%y_%H%M%S)
    echo -e "\n🔄 Backing up existing config files if they exist..."

    mkdir -p ~/.kube ~/.config/rclone

    if [[ -f ~/.kube/config ]]; then
        mv ~/.kube/config ~/.kube/config."$timestamp"
        echo "✅ Backed up ~/.kube/config to ~/.kube/config.$timestamp"
    else
        echo "⚠️  ~/.kube/config not found, skipping backup"
    fi

    if [[ -f ~/.config/rclone/rclone.conf ]]; then
        mv ~/.config/rclone/rclone.conf ~/.config/rclone/rclone.conf."$timestamp"
        echo "✅ Backed up ~/.config/rclone/rclone.conf to ~/.config/rclone/rclone.conf.$timestamp"
    else
        echo "⚠️  ~/.config/rclone/rclone.conf not found, skipping backup"
    fi

    # Set KUBECONFIG explicitly (though aws eks update-kubeconfig will manage this)
    export KUBECONFIG="$HOME/.kube/config"
}

clear_terragrunt_cache() {
    echo "Clearing Terragrunt cache folders..."
    find . -type d -name ".terragrunt-cache" -exec rm -rf {} + || echo "No Terragrunt cache found or failed to delete"
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

    echo "📁 Current working directory: $(pwd)"
    if [[ ! -f terragrunt.hcl ]]; then
        echo "❌ terragrunt.hcl not found in $(pwd). Ensure you are in the correct Terragrunt root module directory."
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
        exit 1
    fi

    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$HOME/.kube/config"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to update kubeconfig for EKS cluster: $EKS_CLUSTER_NAME."
        echo "Verify the cluster name, region, and your AWS credentials."
        exit 1
    fi
    echo "✅ Kubeconfig updated successfully for EKS cluster: $EKS_CLUSTER_NAME."
    # --- END OF CRITICAL ADDITION ---

    if [[ -f ~/.kube/config ]]; then
        chmod 600 ~/.kube/config
        echo "✅ Set permissions for ~/.kube/config"
    else
        echo "❌ Error: ~/.kube/config still not found after update-kubeconfig. This is unexpected and indicates a problem."
        exit 1 # Exit because this indicates a serious problem with kubeconfig generation
    fi
}

certificate_keys() {
    echo "Creating RSA keys for certificate signing..."

    # Ensure 'environment' is defined or passed properly. It's defined globally in this script.
    local cert_dir="../terraform/aws/$environment"
    mkdir -p "$cert_dir" || { echo "❌ Failed to create directory: $cert_dir"; exit 1; }

    # Check if keys already exist to avoid overwriting
    if [[ -f "$cert_dir/certkey.pem" && -f "$cert_dir/certpubkey.pem" ]]; then
        echo "⚠️ Certificate keys already exist in $cert_dir; skipping generation."
    else
        openssl genrsa -out "$cert_dir/certkey.pem" 2048 || { echo "❌ Failed to generate RSA private key."; exit 1; }
        openssl rsa -in "$cert_dir/certkey.pem" -pubout -out "$cert_dir/certpubkey.pem" || { echo "❌ Failed to generate RSA public key."; exit 1; }
        echo "✅ RSA keys generated in $cert_dir."
    fi

    # Escape newlines for YAML
    CERTPRIVATEKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certkey.pem")
    CERTPUBLICKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certpubkey.pem")

    # Alternative with double escape for certain usages (ensure this is needed)
    CERTIFICATESIGNPRKEY=$(sed ':a;N;$!ba;s/\n/\\\\n/g' "$cert_dir/certkey.pem")
    CERTIFICATESIGNPUKEY=$(sed ':a;N;$!ba;s/\n/\\\\n/g' "$cert_dir/certpubkey.pem")

    # Append to global-values.yaml (ensure this file exists or is created by terragrunt)
    if [[ ! -f "$cert_dir/global-values.yaml" ]]; then
        echo "apiVersion: v2" > "$cert_dir/global-values.yaml" # Create if it doesn't exist
    fi

    # Check if keys already exist in global-values.yaml to avoid duplication
    if ! grep -q "CERTIFICATE_PRIVATE_KEY:" "$cert_dir/global-values.yaml"; then
        {
            echo
            echo "  CERTIFICATE_PRIVATE_KEY: \"$CERTPRIVATEKEY\""
            echo "  CERTIFICATE_PUBLIC_KEY: \"$CERTPUBLICKEY\""
            echo "  CERTIFICATESIGN_PRIVATE_KEY: \"$CERTIFICATESIGNPRKEY\""
            echo "  CERTIFICATESIGN_PUBLIC_KEY: \"$CERTIFICATESIGNPUKEY\""
        } >> "$cert_dir/global-values.yaml"
        echo "✅ Certificate keys appended to $cert_dir/global-values.yaml."
    else
        echo "⚠️ Certificate keys already found in $cert_dir/global-values.yaml; skipping append."
    fi
}

certificate_config() {
    echo "Configuring Certificate keys..."

    echo "Waiting for NodeBB deployment to be ready before configuring certificates..."
    kubectl rollout status deployment nodebb -n sunbird --timeout=300s || { echo "❌ NodeBB deployment not ready."; return 1; }

    echo "Updating apt and installing jq on NodeBB pod..."
    kubectl -n sunbird exec deploy/nodebb -- apt update -y || { echo "❌ Failed to update apt on NodeBB."; return 1; }
    kubectl -n sunbird exec deploy/nodebb -- apt install -y jq || { echo "❌ Failed to install jq on NodeBB."; return 1; }

    echo "Checking for existing Certificate RSA public key in Registry Service..."
    CERTKEY=$(kubectl -n sunbird exec deploy/nodebb -- \
      curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey/search' \
      --header 'Content-Type: application/json' --data-raw '{ "filters": {}}' | jq -r '.[0].value // empty')

    if [[ -z "$CERTKEY" ]]; then
        echo "Certificate RSA public key not found. Injecting..."
        local cert_dir="../terraform/aws/$environment"
        CERTPUBKEY=$(awk -F'"' '/CERTIFICATE_PUBLIC_KEY/{print $2}' "$cert_dir/global-values.yaml")
        if [[ -z "$CERTPUBKEY" ]]; then
            echo "❌ Error: CERTIFICATE_PUBLIC_KEY not found in global-values.yaml."
            return 1
        fi
        kubectl -n sunbird exec deploy/nodebb -- curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' \
            --header 'Content-Type: application/json' --data-raw "{\"value\":\"$CERTPUBKEY\"}" || { echo "❌ Failed to inject public key."; return 1; }
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
    fi

    if [[ "$component" == "learnbb" ]]; then
        echo "Processing learnbb specific actions..."
        if kubectl get job keycloak-kids-keys -n sunbird &>/dev/null; then
            echo "Deleting existing job keycloak-kids-keys to ensure clean installation..."
            kubectl delete job keycloak-kids-keys -n sunbird --timeout=60s || echo "⚠️ Failed to delete keycloak-kids-keys job, might already be gone or stuck."
        fi

        # Always ensure certificate_keys is called if not already done, for learnbb specifically
        certificate_keys
    fi

    echo "Running helm upgrade --install for $component..."
    helm upgrade --install "$component" "$component" --namespace sunbird \
        -f "$component/values.yaml" $ed_values_flag \
        -f "../terraform/aws/$environment/global-values.yaml" \
        -f "../terraform/aws/$environment/global-cloud-values.yaml" \
        --timeout 30m --debug --wait --wait-for-jobs || { echo "❌ Helm installation failed for $component."; exit 1; }
    echo "✅ Component $component installed/upgraded successfully."

    # Return to original directory (important for subsequent component installations if paths are relative)
    cd "$cur_dir" || { echo "❌ Failed to return to original directory: $cur_dir"; exit 1; }
}

install_helm_components() {
    # It's better to ensure these are in relative paths to where the script assumes 'helmcharts' is
    # For now, assuming script runs from a directory where 'helmcharts' is ../../../helmcharts
    local components=("monitoring" "edbb" "learnbb" "knowledgebb" "obsrvbb" "inquirybb" "additional")
    for component in "${components[@]}"; do
        install_component "$component"
    done
    echo "✅ All specified Helm components installed."
}

post_install_nodebb_plugins() {
    echo ">> Waiting for NodeBB deployment to be ready..."
    kubectl rollout status deployment nodebb -n sunbird --timeout=600s || { echo "❌ NodeBB deployment not ready after 600s. Skipping plugin activation."; return 1; }

    echo ">> Activating NodeBB plugins..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-create-forum || { echo "❌ Failed to activate nodebb-plugin-create-forum."; return 1; }
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-sunbird-oidc || { echo "❌ Failed to activate nodebb-plugin-sunbird-oidc."; return 1; }
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-write-api || { echo "❌ Failed to activate nodebb-plugin-write-api."; return 1; }

    echo ">> Rebuilding and restarting NodeBB..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb build || { echo "❌ Failed to build NodeBB."; return 1; }
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb restart || { echo "❌ Failed to restart NodeBB."; return 1; }

    echo "✅ NodeBB plugins activated and NodeBB restarted."
}

dns_mapping() {
    echo -e "\nVerifying DNS mapping..."
    local domain_name
    # Wait for cm 'lms-env' to exist and have the data
    timeout_seconds=300
    start_time=$(date +%s)
    while true; do
        if kubectl get cm -n sunbird lms-env &>/dev/null; then
            domain_name=$(kubectl get cm -n sunbird lms-env -ojsonpath='{.data.sunbird_web_url}')
            if [[ -n "$domain_name" ]]; then
                break
            fi
        fi
        current_time=$(date +%s)
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
    while true; do
        public_ip=$(kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [[ -n "$public_ip" ]]; then
            break
        fi
        current_time=$(date +%s)
        if (( current_time - start_time >= timeout_seconds )); then
            echo "❌ Timeout waiting for nginx-public-ingress external IP."
            return 1
        fi
        echo "Waiting for nginx-public-ingress to get an external IP..."
        sleep 10
    done

    local timeout=$((SECONDS + 1200))  # 20 minutes timeout for DNS propagation
    local check_interval=10

    echo -e "\nAdd or update your DNS A record for domain $domain_name to point to IP: $public_ip"

    echo "Waiting for DNS $domain_name to resolve to $public_ip..."
    while ! nslookup "$domain_name" 2>/dev/null | grep -q "$public_ip"; do
        if (( SECONDS >= timeout )); then
            echo "❌ Timeout reached: DNS entry for $domain_name does not point to $public_ip"
            echo "Please manually configure your DNS A record for $domain_name to point to $public_ip."
            return 1
        fi
        echo "Still waiting for DNS $domain_name to point to $public_ip... (Checking every $check_interval seconds)"
        sleep $check_interval
    done

    echo "✅ DNS mapping for $domain_name is set to $public_ip"
}

check_pod_status() {
    local namespace="sunbird"
    # Added nodebb to components for status check since it's critical
    local components=("learnbb" "knowledgebb" "nodebb" "obsrvbb" "inquirybb" "edbb" "monitoring" "additional")

    echo -e "\n🧪 Checking pod status in namespace $namespace..."
    local overall_success=true
    for pod_label in "${components[@]}"; do
        echo -e "\nChecking pod(s) with label app=$pod_label in namespace $namespace"
        # Using a safer way to wait for pods, ensuring they are available before checking readiness
        if ! kubectl wait --for=condition=available deployment -l app="$pod_label" -n "$namespace" --timeout=300s 2>/dev/null && \
           ! kubectl wait --for=condition=ready pod -l app="$pod_label" -n "$namespace" --timeout=300s; then
            echo "❌ Pod(s) with app=$pod_label are not ready after 300 seconds"
            kubectl get pods -l app="$pod_label" -n "$namespace"
            kubectl describe pods -l app="$pod_label" -n "$namespace" | head -n 30 # Show top of describe for quick debug
            overall_success=false
        else
            echo "✅ Pod(s) with app=$pod_label are ready"
        fi
    done

    if ! "$overall_success"; then
        echo "⚠️ Some pods are not in a ready state. Manual inspection recommended."
        exit 1 # Consider exiting if critical pods are not ready
    fi
    echo "✅ All essential pods in namespace $namespace are reported as ready."
}

# --- Main execution flow ---
main() {
    echo "Starting installation process..."

    # Ensure AWS CLI is present for update-kubeconfig later
    if ! command -v aws &>/dev/null; then
        echo "❌ AWS CLI not found. Please install it (e.g., 'sudo apt install awscli')."
        exit 1
    fi

    create_tf_backend
    backup_configs
    create_tf_resources # This will now create/update ~/.kube/config

    # After create_tf_resources, kubectl should now be able to connect
    echo -e "\nVerifying Kubernetes cluster connectivity after provisioning..."
    kubectl cluster-info || { echo "❌ kubectl cluster-info failed after provisioning. Manual debug required."; exit 1; }
    kubectl get nodes || { echo "❌ kubectl get nodes failed after provisioning. Manual debug required."; exit 1; }
    echo "✅ Kubernetes cluster connection verified."

    install_helm_components
    certificate_config # Ensure this runs after NodeBB is potentially ready
    post_install_nodebb_plugins
    dns_mapping
    check_pod_status

    echo -e "\n🎉 All tasks completed successfully! Your Sunbird platform should now be accessible."
}

main "$@"
