#!/bin/bash
set -euo pipefail

# --- AWS Credential Handling ---
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
    read -rp "Enter your AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
fi

if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    read -rsp "Enter your AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
    echo
fi

if [[ -z "${AWS_REGION:-}" ]]; then
    read -rp "Enter your AWS_REGION (e.g., ap-south-1): " AWS_REGION
fi

export TF_VAR_aws_access_key_id="$AWS_ACCESS_KEY_ID"
export TF_VAR_aws_secret_access_key="$AWS_SECRET_ACCESS_KEY"
export TF_VAR_aws_region="$AWS_REGION"

# --- Global Variables ---
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
environment=$(basename "$(pwd)")
HELM_CHARTS_BASE_DIR="$(realpath "$SCRIPT_DIR/../../../helmcharts")"

# --- Functions ---

check_aws_credentials() {
    echo -e "\nChecking AWS credentials and region..."
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" || -z "${AWS_REGION:-}" ]]; then
        echo "❌ AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) or AWS_REGION not found in environment variables."
        echo "Please ensure you have configured your AWS CLI using 'aws configure' or exported these variables."
        exit 1
    fi
    echo "✅ AWS credentials and region are set."
}

create_tf_backend() {
    echo "Creating Terraform state backend..."
    if [[ ! -f tf_backend.sh ]]; then
        echo "❌ Error: tf_backend.sh not found in $(pwd). Make sure it exists and is executable."
        exit 1
    fi
    bash tf_backend.sh || { echo "❌ Terraform state backend creation failed."; exit 1; }
    echo "✅ Terraform state backend created."

    echo "Sourcing tf.sh to load backend environment variables..."
    if [[ ! -f tf.sh ]]; then
        echo "❌ Error: tf.sh not found. Cannot load backend environment variables."
        exit 1
    fi
    source tf.sh || { echo "❌ Failed to source tf.sh. Backend environment variables might not be loaded."; exit 1; }
    echo "✅ Backend environment variables loaded."
}

backup_configs() {
    echo -e "\nBacking up existing config files..."
    local timestamp=$(date +%Y%m%d%H%M%S)

    if [[ -f "$HOME/.kube/config" ]]; then
        mkdir -p "$HOME/.kube"
        mv "$HOME/.kube/config" "$HOME/.kube/config.$timestamp"
        echo "✅ Backed up ~/.kube/config to ~/.kube/config.$timestamp"
    else
        echo "⚠️ ~/.kube/config not found, skipping backup."
    fi

    if [[ -f "$HOME/.config/rclone/rclone.conf" ]]; then
        mkdir -p "$HOME/.config/rclone"
        mv "$HOME/.config/rclone/rclone.conf" "$HOME/.config/rclone/rclone.conf.$timestamp"
        echo "✅ Backed up ~/.config/rclone/rclone.conf to ~/.config/rclone/rclone.conf.$timestamp"
    else
        echo "⚠️ ~/.config/rclone/rclone.conf not found, skipping backup."
    fi
}

clear_terragrunt_cache() {
    echo "Clearing Terragrunt cache folders..."
    find . -depth 2 -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || echo "No Terragrunt cache found or failed to delete (may not exist)"
    echo "✅ Terragrunt cache cleared."
}

create_tf_resources() {
    echo -e "\nCreating AWS resources using Terragrunt..."

    local current_dir=$(pwd)
    if [[ $(basename "$current_dir") != "template" || ! -f "terragrunt.hcl" ]]; then
        echo "❌ Error: This script expects to be run from the 'template' directory (e.g., ~/AA_Sunbird_Demo/terraform/aws/template)."
        echo "Current directory: $current_dir"
        exit 1
    fi
    echo "📁 Current working directory: $(pwd)"

    clear_terragrunt_cache

    echo "Running terragrunt init..."
    terragrunt init || { echo "❌ Terragrunt init failed."; exit 1; }

    echo "Running terragrunt apply --all -auto-approve --terragrunt-non-interactive..."
    terragrunt apply --all -auto-approve --terragrunt-non-interactive || { echo "❌ Terragrunt apply failed."; exit 1; }
    echo "✅ AWS resources created successfully."

    echo "Attempting to configure kubectl for the newly created EKS cluster..."

    if [[ -z "$EKS_CLUSTER_NAME" || "$EKS_CLUSTER_NAME" == "demo-sunbirdedAA-eks" ]]; then
        echo "❌ Error: EKS_CLUSTER_NAME variable not set or is still a placeholder in install.sh."
        echo "Please edit install.sh and set EKS_CLUSTER_NAME to your actual EKS cluster name."
        exit 1
    fi
    echo "Identified EKS Cluster Name: $EKS_CLUSTER_NAME (from user configuration)"

    if ! command -v aws &>/dev/null; then
        echo "❌ Error: AWS CLI not found. Please install AWS CLI to update kubeconfig."
        exit 1
    fi

    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$HOME/.kube/config" \
        || { echo "❌ Failed to update kubeconfig for EKS cluster: $EKS_CLUSTER_NAME. Verify the cluster name, region, and your AWS credentials."; exit 1; }
    echo "✅ Kubeconfig updated successfully for EKS cluster: $EKS_CLUSTER_NAME."
}

certificate_keys() {
    echo "Creating RSA keys for certificate signing..."

    local cert_dir="$SCRIPT_DIR"
    mkdir -p "$cert_dir" || { echo "❌ Failed to create directory: $cert_dir"; exit 1; }

    if [[ -f "$cert_dir/certkey.pem" && -f "$cert_dir/certpubkey.pem" ]]; then
        echo "✅ RSA keys already exist in $cert_dir. Skipping generation."
    else
        echo "Generating new RSA keys..."
        openssl genrsa -out "$cert_dir/certkey.pem" 2048 || { echo "❌ Failed to generate RSA private key."; exit 1; }
        openssl rsa -in "$cert_dir/certkey.pem" -pubout -out "$cert_dir/certpubkey.pem" || { echo "❌ Failed to generate RSA public key."; exit 1; }
        echo "✅ RSA keys generated in $cert_dir."
    fi

    CERTPRIVATEKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certkey.pem")
    CERTPUBLICKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certpubkey.pem")

    local global_values_file="$cert_dir/global-values.yaml"
    if [[ ! -f "$global_values_file" ]]; then
        echo "❌ Error: $global_values_file not found. Cannot inject certificate keys."
        exit 1
    fi

    awk -v privkey="$CERTPRIVATEKEY" -v pubkey="$CERTPUBLICKEY" '
    BEGIN {
        private_key_set = 0;
        public_key_set = 0;
    }
    /CERTIFICATE_PRIVATE_KEY:/ {
        print "  CERTIFICATE_PRIVATE_KEY: \"" privkey "\""
        private_key_set = 1
        next
    }
    /CERTIFICATE_PUBLIC_KEY:/ {
        print "  CERTIFICATE_PUBLIC_KEY: \"" pubkey "\""
        public_key_set = 1
        next
    }
    { print }
    END {
        if (private_key_set == 0) {
            print "  CERTIFICATE_PRIVATE_KEY: \"" privkey "\""
        }
        if (public_key_set == 0) {
            print "  CERTIFICATE_PUBLIC_KEY: \"" pubkey "\""
        }
    }
    ' "$global_values_file" > "${global_values_file}.tmp" && mv "${global_values_file}.tmp" "$global_values_file"

    echo "✅ Injected certificate keys into $global_values_file."
}

wait_for_app_ready() {
    local deployment_name="$1"
    local namespace="$2"
    local timeout_seconds="$3"

    echo "Waiting for deployment '$deployment_name' in namespace '$namespace' to be ready..."
    kubectl rollout status deployment "$deployment_name" -n "$namespace" --timeout="${timeout_seconds}s" \
        || { echo "❌ Deployment $deployment_name not ready after ${timeout_seconds}s."; return 1; }
    echo "✅ Deployment $deployment_name is ready."

    if [[ "$deployment_name" == "nodebb" ]]; then
        echo "Waiting for NodeBB application to be fully available (port 4567)..."
        local start_time=$(date +%s)
        local nodebb_pod=""
        while true; do
            nodebb_pod=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=nodebb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [[ -n "$nodebb_pod" ]]; then
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
    wait_for_app_ready "nodebb" "sunbird" "300" || { echo "❌ NodeBB not ready for certificate configuration."; return 1; }

    local nodebb_pod=$(kubectl get pods -n sunbird -l app.kubernetes.io/name=nodebb -o jsonpath='{.items[0].metadata.name}')
    if [[ -z "$nodebb_pod" ]]; then
        echo "❌ Could not find NodeBB pod. Cannot configure certificates."
        return 1
    fi

    echo "Updating apt and installing jq on NodeBB pod ($nodebb_pod)..."
    kubectl -n sunbird exec "$nodebb_pod" -- apt update -y || { echo "❌ Failed to update apt on NodeBB."; return 1; }
    kubectl -n sunbird exec "$nodebb_pod" -- apt install -y jq || { echo "❌ Failed to install jq on NodeBB."; return 1; }

    echo "Checking for existing Certificate RSA public key in Registry Service..."
    CERTKEY=$(kubectl -n sunbird exec "$nodebb_pod" -- \
        curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey/search' \
        --header 'Content-Type: application/json' --data-raw '{ "filters": {}}' | jq -r '.[0].value // empty')

    if [[ -z "$CERTKEY" ]]; then
        echo "Certificate RSA public key not found. Injecting..."
        local cert_dir="$SCRIPT_DIR"
        local global_values_file="$cert_dir/global-values.yaml"

        CERTPUBKEY=$(grep 'CERTIFICATE_PUBLIC_KEY:' "$global_values_file" | awk -F'"' '{print $2}')
        if [[ -z "$CERTPUBKEY" ]]; then
            echo "❌ Error: CERTIFICATE_PUBLIC_KEY not found or empty in $global_values_file."
            return 1
        fi

        kubectl -n sunbird exec "$nodebb_pod" -- curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' \
            --header 'Content-Type: application/json' --data-raw "{\"value\":\"$CERTPUBKEY\"}" || { echo "❌ Failed to inject public key."; return 1; }
        echo "✅ Certificate RSA public key injected."
    else
        echo "✅ Certificate RSA public key already exists. Skipping injection."
    fi
}

install_component() {
    if ! command -v helm &>/dev/null; then
        echo "❌ Helm not found. Please install Helm before proceeding."
        exit 1
    fi

    kubectl create namespace sunbird 2>/dev/null || true
    kubectl create namespace velero 2>/dev/null || true
    kubectl create configmap keycloak-key -n sunbird 2>/dev/null || true

    local component="$1"
    echo -e "\n--- Installing/Upgrading component: $component ---"

    local ed_values_flag=""
    if [[ -f "$HELM_CHARTS_BASE_DIR/$component/ed-values.yaml" ]]; then
        ed_values_flag="-f $HELM_CHARTS_BASE_DIR/$component/ed-values.yaml"
    fi

    if [[ "$component" == "learnbb" ]]; then
        echo "Processing learnbb specific actions..."
        if kubectl get job keycloak-kids-keys -n sunbird &>/dev/null; then
            echo "Deleting existing job keycloak-kids-keys to ensure clean installation..."
            kubectl delete job keycloak-kids-keys -n sunbird --timeout=60s --ignore-not-found || echo "⚠️ Failed to delete keycloak-kids-keys job, might be stuck."
        fi
        certificate_keys
    fi

    echo "Running helm upgrade --install for $component..."
    helm upgrade --install "$component" "$HELM_CHARTS_BASE_DIR/$component" --namespace sunbird \
        -f "$HELM_CHARTS_BASE_DIR/$component/values.yaml" $ed_values_flag \
        -f "$SCRIPT_DIR/global-values.yaml" \
        -f "$SCRIPT_DIR/global-cloud-values.yaml" \
        --timeout 30m --debug --wait --wait-for-jobs || { echo "❌ Helm installation failed for $component."; exit 1; }
    echo "✅ Component $component installed/upgraded successfully."
}

install_helm_components() {
    echo -e "\n--- Installing Helm Components ---"
    kubectl create namespace sunbird 2>/dev/null || true
    kubectl create namespace velero 2>/dev/null || true
    kubectl create configmap keycloak-key -n sunbird 2>/dev/null || true

    local components=("monitoring" "edbb" "learnbb" "knowledgebb" "obsrvbb" "inquirybb" "additional")
    for component in "${components[@]}"; do
        install_component "$component"
    done
    echo "✅ All Helm components installed/upgraded."
}

post_install_nodebb_plugins() {
    echo ">> Waiting for NodeBB deployment to be ready before activating plugins..."
    wait_for_app_ready "nodebb" "sunbird" "600" || { echo "❌ NodeBB not ready for plugin activation. Skipping plugin activation."; return 1; }

    local nodebb_pod=$(kubectl get pods -n sunbird -l app.kubernetes.io/name=nodebb -o jsonpath='{.items[0].metadata.name}')
    if [[ -z "$nodebb_pod" ]]; then
        echo "❌ Could not find NodeBB pod. Cannot activate plugins."
        return 1
    fi

    echo ">> Activating NodeBB plugins for pod $nodebb_pod..."
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb activate nodebb-plugin-create-forum || { echo "❌ Failed to activate nodebb-plugin-create-forum."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb activate nodebb-plugin-sunbird-oidc || { echo "❌ Failed to activate nodebb-plugin-sunbird-oidc."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb activate nodebb-plugin-write-api || { echo "❌ Failed to activate nodebb-plugin-write-api."; return 1; }

    echo ">> Rebuilding and restarting NodeBB for pod $nodebb_pod..."
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb build || { echo "❌ Failed to build NodeBB."; return 1; }
    kubectl exec -n sunbird "$nodebb_pod" -- ./nodebb restart || { echo "❌ Failed to restart NodeBB."; return 1; }

    echo "✅ NodeBB plugins activated and NodeBB restarted."
}

dns_mapping() {
    echo -e "\nVerifying DNS mapping..."
    local domain_name
    local timeout_seconds=300
    local start_time=$(date +%s)

    echo "Waiting for lms-env configmap to be available and contain sunbird_web_url..."
    while true; do
        if kubectl get cm -n sunbird lms-env -o jsonpath='{.data.sunbird_web_url}' &>/dev/null; then
            domain_name=$(kubectl get cm -n sunbird lms-env -ojsonpath='{.data.sunbird_web_url}')
            if [[ -n "$domain_name" ]]; then
                echo "✅ Found domain name: $domain_name"
                break
            fi
        fi
        local current_time=$(date +%s)
        if (( current_time - start_time >= timeout_seconds )); then
            echo "❌ Timeout waiting for lms-env configmap or sunbird_web_url."
            return 1
        fi
        echo "Waiting for lms-env configmap to be available and contain sunbird_web_url..."
        sleep 10
    done

    local public_ip
    start_time=$(date +%s)
    echo "Waiting for nginx-public-ingress to get an external IP..."
    while true; do
        public_ip=$(kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [[ -n "$public_ip" ]]; then
            echo "✅ Found public IP for ingress: $public_ip"
            break
        fi
        local current_time=$(date +%s)
        if (( current_time - start_time >= timeout_seconds )); then
            echo "❌ Timeout waiting for nginx-public-ingress external IP."
            return 1
        fi
        echo "Waiting for nginx-public-ingress to get an external IP..."
        sleep 10
    done

    local dns_propagation_timeout=$((SECONDS + 1200))
    local check_interval=10

    echo -e "\nAdd or update your DNS A record for domain $domain_name to point to IP: $public_ip"

    echo "Waiting for DNS $domain_name to resolve to $public_ip..."
    while ! nslookup "$domain_name" 2>/dev/null | grep -q "$public_ip"; do
        if (( SECONDS >= dns_propagation_timeout )); then
            echo "❌ Timeout reached: DNS entry for $domain_name does not point to $public_ip"
            echo "Please manually configure your DNS A record for $domain_name to point to $public_ip."
            return 1
        fi
        echo "Still waiting for DNS propagation (checking every ${check_interval}s)..."
        sleep "$check_interval"
    done
    echo "✅ DNS for $domain_name now resolves to $public_ip."
}

check_pod_status() {
    local namespace="sunbird"
    local components=("learnbb" "knowledgebb" "nodebb" "obsrvbb" "inquirybb" "edbb" "monitoring" "additional")

    echo -e "\n🧪 Checking pod status in namespace $namespace..."
    local overall_success=true
    for pod_label in "${components[@]}"; do
        echo -e "\nChecking pod(s) with label app.kubernetes.io/name=$pod_label in namespace $namespace"
        if ! kubectl wait --for=condition=available deployment -l app.kubernetes.io/name="$pod_label" -n "$namespace" --timeout=300s 2>/dev/null; then
            echo "❌ Deployment(s) with app.kubernetes.io/name=$pod_label are not available after 300 seconds. Pods may not exist or be starting."
            kubectl get pods -l app.kubernetes.io/name="$pod_label" -n "$namespace"
            overall_success=false
        elif ! kubectl wait --for=condition=ready pod -l app.kubernetes.io/name="$pod_label" -n "$namespace" --timeout=300s; then
            echo "❌ Pod(s) with app.kubernetes.io/name=$pod_label are not ready after 300 seconds"
            kubectl get pods -l app.kubernetes.io/name="$pod_label" -n "$namespace"
            kubectl describe pods -l app.kubernetes.io/name="$pod_label" -n "$namespace" | head -n 30
            overall_success=false
        else
            echo "✅ Deployment(s) with app.kubernetes.io/name=$pod_label and their pods are ready."
        fi
    done

    if ! "$overall_success"; then
        echo "⚠️ Some critical pods are not in a ready state. Manual inspection recommended."
        exit 1
    fi
    echo "✅ All essential pods in namespace $namespace are reported as ready."
}

# --- Main execution flow ---
main() {
    echo "Starting Sunbird installation process..."

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

    check_aws_credentials

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
    create_tf_resources

    echo -e "\nVerifying Kubernetes cluster connectivity after provisioning..."
    kubectl cluster-info || { echo "❌ kubectl cluster-info failed after provisioning. Manual debug required."; exit 1; }
    kubectl get nodes || { echo "❌ kubectl get nodes failed after provisioning. Manual debug required."; exit 1; }
    echo "✅ Kubernetes cluster connection verified."

    echo "Navigating to Helm charts directory: $HELM_CHARTS_BASE_DIR"
    cd "$HELM_CHARTS_BASE_DIR" || { echo "❌ Cannot navigate to Helm charts directory: $HELM_CHARTS_BASE_DIR"; exit 1; }
    echo "Current working directory: $(pwd)"

    install_helm_components
    certificate_config
    post_install_nodebb_plugins
    dns_mapping
    check_pod_status

    echo -e "\n🎉 All tasks completed successfully! Your Sunbird platform should now be accessible."
}

main "$@"
