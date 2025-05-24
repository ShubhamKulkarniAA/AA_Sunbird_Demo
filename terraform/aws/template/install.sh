#!/bin/bash
set -euo pipefail

echo -e "\nPlease ensure you have updated all the mandatory variables as mentioned in the documentation."
echo "The installation will fail if any of the mandatory variables are missing."
echo "Press Enter to continue..."
read -r

environment=$(basename "$(pwd)")

function create_tf_backend() {
    echo -e "Creating terraform state backend"
    bash tf_backend.sh
}

function backup_configs() {
    timestamp=$(date +%d%m%y_%H%M%S)
    echo -e "\n🔄 Backup existing config files if they exist"

    # Ensure .kube and .config/rclone directories exist
    mkdir -p ~/.kube
    mkdir -p ~/.config/rclone

    # Backup kube config if it exists
    if [ -f ~/.kube/config ]; then
        mv ~/.kube/config ~/.kube/config.$timestamp
        echo "✅ Backed up ~/.kube/config to ~/.kube/config.$timestamp"
    else
        echo "⚠️  ~/.kube/config not found, skipping backup"
    fi

    # Backup rclone config if it exists
    if [ -f ~/.config/rclone/rclone.conf ]; then
        mv ~/.config/rclone/rclone.conf ~/.config/rclone/rclone.conf.$timestamp
        echo "✅ Backed up ~/.config/rclone/rclone.conf to ~/.config/rclone/rclone.conf.$timestamp"
    else
        echo "⚠️  ~/.config/rclone/rclone.conf not found, skipping backup"
    fi

    # Export KUBECONFIG
    export KUBECONFIG=~/.kube/config
}

function create_tf_resources() {
    source tf.sh
    echo -e "\nCreating resources on aws cloud"

    # Navigate to the directory where terragrunt.hcl is actually located
    TEMPLATE_DIR="$(dirname "$0")"
    cd "$TEMPLATE_DIR" || { echo "❌ Cannot find template directory"; exit 1; }

    echo "📁 Current working directory: $(pwd)"
    echo "📄 Checking for terragrunt.hcl..."
    if [ ! -f terragrunt.hcl ]; then
        echo "❌ terragrunt.hcl not found in $(pwd)"
        exit 1
    fi

    terraform init -migrate-state
    terragrunt init -upgrade
    terragrunt apply --all -auto-approve --terragrunt-non-interactive

    [ -f ~/.kube/config ] && chmod 600 ~/.kube/config || echo "⚠️  ~/.kube/config not found, skipping chmod"
}


function certificate_keys() {
    # Generate private and public keys using openssl
    echo "Creation of RSA keys for certificate signing"
    openssl genrsa -out ../terraform/aws/$environment/certkey.pem
    openssl rsa -in ../terraform/aws/$environment/certkey.pem -pubout -out ../terraform/aws/$environment/certpubkey.pem

    CERTPRIVATEKEY=$(sed 's/KEY-----/KEY-----\\n/g' ../terraform/aws/$environment/certkey.pem | sed 's/-----END/\\n-----END/g' | awk '{printf("%s",$0)}')
    CERTPUBLICKEY=$(sed 's/KEY-----/KEY-----\\n/g' ../terraform/aws/$environment/certpubkey.pem | sed 's/-----END/\\n-----END/g' | awk '{printf("%s",$0)}')
    CERTIFICATESIGNPRKEY=$(sed 's/BEGIN PRIVATE KEY-----/BEGIN PRIVATE KEY-----\\\\n/g' ../terraform/aws/$environment/certkey.pem | sed 's/-----END PRIVATE KEY/\\\\n-----END PRIVATE KEY/g' | awk '{printf("%s",$0)}')
    CERTIFICATESIGNPUKEY=$(sed 's/BEGIN PUBLIC KEY-----/BEGIN PUBLIC KEY-----\\\\n/g' ../terraform/aws/$environment/certpubkey.pem | sed 's/-----END PUBLIC KEY/\\\\n-----END PUBLIC KEY/g' | awk '{printf("%s",$0)}')

    printf "\n" >> ../terraform/aws/$environment/global-values.yaml
    echo "  CERTIFICATE_PRIVATE_KEY: \"$CERTPRIVATEKEY\"" >> ../terraform/aws/$environment/global-values.yaml
    echo "  CERTIFICATE_PUBLIC_KEY: \"$CERTPUBLICKEY\"" >> ../terraform/aws/$environment/global-values.yaml
    echo "  CERTIFICATESIGN_PRIVATE_KEY: \"$CERTIFICATESIGNPRKEY\"" >> ../terraform/aws/$environment/global-values.yaml
    echo "  CERTIFICATESIGN_PUBLIC_KEY: \"$CERTIFICATESIGNPUKEY\"" >> ../terraform/aws/$environment/global-values.yaml
}

function certificate_config() {
    # Check if the key is already present in RC
    echo "Configuring Certificatekeys"
    kubectl -n sunbird exec deploy/nodebb -- apt update -y
    kubectl -n sunbird exec deploy/nodebb -- apt install jq -y
    CERTKEY=$(kubectl -n sunbird exec deploy/nodebb -- curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey/search' --header 'Content-Type: application/json' --data-raw '{ "filters": {}}' | jq '.[] | .value')

    # Inject cert keys to the service if its not available
    if [ -z "$CERTKEY" ]; then
        echo "Certificate RSA public key not available"
        CERTPUBKEY=$(awk -F'"' '/CERTIFICATE_PUBLIC_KEY/{print $2}' ../terraform/aws/$environment/global-values.yaml)
        curl_data="curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' --header 'Content-Type: application/json' --data-raw '{\"value\":\"$CERTPUBKEY\"}'"
        echo "kubectl -n sunbird exec deploy/nodebb -- $curl_data" | sh -
    fi
}

function install_component() {
    # Verify helm is installed
    if ! command -v helm &> /dev/null; then
        echo "❌ Helm is not installed or not found in PATH. Please install Helm before proceeding."
        exit 1
    fi

    # We need a dummy configmap to start. Later learnbb will create real one
    kubectl create configmap keycloak-key -n sunbird 2>/dev/null || true

    local current_directory
    current_directory="$(pwd)"
    if [ "$(basename "$current_directory")" != "helmcharts" ]; then
        cd ../../../helmcharts 2>/dev/null || true
    fi

    local component="$1"
    kubectl create namespace sunbird 2>/dev/null || true
    kubectl create namespace velero 2>/dev/null || true
    echo -e "\nInstalling $component"

    local ed_values_flag=""
    if [ -f "$component/ed-values.yaml" ]; then
        ed_values_flag="-f $component/ed-values.yaml --wait --wait-for-jobs"
    fi

    # Generate the key pair required for certificate template
    if [ "$component" = "learnbb" ]; then
        if kubectl get job keycloak-kids-keys -n sunbird >/dev/null 2>&1; then
            echo "Deleting existing job keycloak-kids-keys..."
            kubectl delete job keycloak-kids-keys -n sunbird
        fi

        if [ -f "certkey.pem" ] && [ -f "certpubkey.pem" ]; then
            echo "✅ Certificate keys are already created. Skipping the keys creation..."
        else
            certificate_keys
        fi
    fi

    helm upgrade --install "$component" "$component" --namespace sunbird -f "$component/values.yaml" \
        $ed_values_flag \
        -f "../terraform/aws/$environment/global-values.yaml" \
        -f "../terraform/aws/$environment/global-cloud-values.yaml" --timeout 30m --debug
}

function install_helm_components() {
    components=("monitoring" "edbb" "learnbb" "knowledgebb" "obsrvbb" "inquirybb" "additional")
    for component in "${components[@]}"; do
        install_component "$component"
    done
}

function post_install_nodebb_plugins() {
    echo ">> Waiting for NodeBB to be ready..."
    kubectl rollout status deployment nodebb -n sunbird --timeout=300s

    echo ">> Activating NodeBB plugins..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-create-forum
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-sunbird-oidc
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-write-api

    echo ">> Rebuilding and restarting NodeBB..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb build
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb restart

    echo "✅ NodeBB plugins are activated and NodeBB has been restarted."
}

function dns_mapping() {
    domain_name=$(kubectl get cm -n sunbird lms-env -ojsonpath='{.data.sunbird_web_url}')
    PUBLIC_IP=$(kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].ip}')

    local timeout=$((SECONDS + 1200))  # 20 minutes from now
    local check_interval=10

    echo -e "\nAdd/update your DNS mapping for your domain by adding an A record to this IP: $PUBLIC_IP"

    # Wait until domain_name resolves to the PUBLIC_IP or timeout
    while ! nslookup "$domain_name" | grep -q "$PUBLIC_IP"; do
        if [ $SECONDS -ge $timeout ]; then
            echo "❌ Timeout reached: DNS entry for $domain_name does not point to $PUBLIC_IP"
            break
        fi
        echo "Waiting for DNS $domain_name to point to $PUBLIC_IP..."
        sleep $check_interval
    done
    echo "✅ DNS mapping for $domain_name is set to $PUBLIC_IP"
}

function check_pod_status() {
    namespace="sunbird"
    components=("learnbb" "knowledgebb" "nodebb" "obsrvbb" "inquirybb" "edbb" "monitoring" "additional")

    echo -e "\n🧪 Checking pod status for sunbird pods"
    for pod in "${components[@]}"; do
        echo -e "\nChecking pod: $pod in namespace: $namespace"
        kubectl wait --for=condition=ready pod -l app="$pod" -n "$namespace" --timeout=300s || {
            echo "❌ Pod $pod is not ready after 300 seconds"
        }
    done
}

function run_post_install() {
    post_install_nodebb_plugins
    certificate_config
    dns_mapping
    check_pod_status
}

function cleanworkspace() {
    echo "Cleaning workspace..."
    rm -rf ../terraform/aws/"$environment"/global-values.yaml
}

function destroy_tf_resources() {
    echo -e "\nDestroying resources on aws cloud"
    terragrunt run-all destroy --terragrunt-non-interactive || {
        echo "⚠️ Destroy failed or aborted"
    }
}

function invoke_functions() {
    backup_configs
    create_tf_backend
    create_tf_resources
    install_helm_components
    run_post_install
}

trap cleanworkspace EXIT

invoke_functions
