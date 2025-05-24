#!/bin/bash
set -euo pipefail

echo -e "\nPlease ensure you have updated all the mandatory variables as mentioned in the documentation."
echo "The installation will fail if any of the mandatory variables are missing."
echo "Press Enter to continue..."
read -r

environment=$(basename "$(pwd)")

create_tf_backend() {
    echo "Creating terraform state backend..."
    bash tf_backend.sh
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

    export KUBECONFIG="$HOME/.kube/config"
}

create_tf_resources() {
    source tf.sh
    echo -e "\nCreating resources on AWS cloud..."

    local script_dir
    script_dir=$(dirname "${BASH_SOURCE[0]}")
    cd "$script_dir" || { echo "❌ Cannot find script directory"; exit 1; }

    echo "📁 Current working directory: $(pwd)"
    if [[ ! -f terragrunt.hcl ]]; then
        echo "❌ terragrunt.hcl not found in $(pwd)"
        exit 1
    fi

    terraform init -reconfigure
    terragrunt init -upgrade
    terragrunt apply --all -auto-approve --terragrunt-non-interactive

    if [[ -f ~/.kube/config ]]; then
        chmod 600 ~/.kube/config
    else
        echo "⚠️  ~/.kube/config not found, skipping chmod"
    fi
}

certificate_keys() {
    echo "Creating RSA keys for certificate signing..."

    local cert_dir="../terraform/aws/$environment"
    mkdir -p "$cert_dir"

    openssl genrsa -out "$cert_dir/certkey.pem" 2048
    openssl rsa -in "$cert_dir/certkey.pem" -pubout -out "$cert_dir/certpubkey.pem"

    # Escape newlines for YAML
    CERTPRIVATEKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certkey.pem")
    CERTPUBLICKEY=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_dir/certpubkey.pem")

    # Alternative with double escape for certain usages
    CERTIFICATESIGNPRKEY=$(sed ':a;N;$!ba;s/\n/\\\\n/g' "$cert_dir/certkey.pem")
    CERTIFICATESIGNPUKEY=$(sed ':a;N;$!ba;s/\n/\\\\n/g' "$cert_dir/certpubkey.pem")

    {
        echo
        echo "  CERTIFICATE_PRIVATE_KEY: \"$CERTPRIVATEKEY\""
        echo "  CERTIFICATE_PUBLIC_KEY: \"$CERTPUBLICKEY\""
        echo "  CERTIFICATESIGN_PRIVATE_KEY: \"$CERTIFICATESIGNPRKEY\""
        echo "  CERTIFICATESIGN_PUBLIC_KEY: \"$CERTIFICATESIGNPUKEY\""
    } >> "$cert_dir/global-values.yaml"
}

certificate_config() {
    echo "Configuring Certificate keys..."

    kubectl -n sunbird exec deploy/nodebb -- apt update -y
    kubectl -n sunbird exec deploy/nodebb -- apt install -y jq

    CERTKEY=$(kubectl -n sunbird exec deploy/nodebb -- \
      curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey/search' \
      --header 'Content-Type: application/json' --data-raw '{ "filters": {}}' | jq -r '.[0].value // empty')

    if [[ -z "$CERTKEY" ]]; then
        echo "Certificate RSA public key not found. Injecting..."
        CERTPUBKEY=$(awk -F'"' '/CERTIFICATE_PUBLIC_KEY/{print $2}' "../terraform/aws/$environment/global-values.yaml")
        kubectl -n sunbird exec deploy/nodebb -- curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' \
            --header 'Content-Type: application/json' --data-raw "{\"value\":\"$CERTPUBKEY\"}"
    else
        echo "Certificate RSA public key already present."
    fi
}

install_component() {
    if ! command -v helm &>/dev/null; then
        echo "❌ Helm not found. Please install Helm before proceeding."
        exit 1
    fi

    kubectl create configmap keycloak-key -n sunbird 2>/dev/null || true

    local cur_dir
    cur_dir=$(pwd)
    if [[ $(basename "$cur_dir") != "helmcharts" ]]; then
        cd ../../../helmcharts || true
    fi

    local component="$1"

    kubectl create namespace sunbird 2>/dev/null || true
    kubectl create namespace velero 2>/dev/null || true

    echo -e "\nInstalling component: $component"

    local ed_values_flag=""
    if [[ -f "$component/ed-values.yaml" ]]; then
        ed_values_flag="-f $component/ed-values.yaml --wait --wait-for-jobs"
    fi

    if [[ "$component" == "learnbb" ]]; then
        if kubectl get job keycloak-kids-keys -n sunbird &>/dev/null; then
            echo "Deleting existing job keycloak-kids-keys..."
            kubectl delete job keycloak-kids-keys -n sunbird
        fi

        if [[ -f "certkey.pem" && -f "certpubkey.pem" ]]; then
            echo "✅ Certificate keys already created; skipping creation."
        else
            certificate_keys
        fi
    fi

    helm upgrade --install "$component" "$component" --namespace sunbird \
        -f "$component/values.yaml" $ed_values_flag \
        -f "../terraform/aws/$environment/global-values.yaml" \
        -f "../terraform/aws/$environment/global-cloud-values.yaml" \
        --timeout 30m --debug
}

install_helm_components() {
    local components=("monitoring" "edbb" "learnbb" "knowledgebb" "obsrvbb" "inquirybb" "additional")
    for component in "${components[@]}"; do
        install_component "$component"
    done
}

post_install_nodebb_plugins() {
    echo ">> Waiting for NodeBB deployment to be ready..."
    kubectl rollout status deployment nodebb -n sunbird --timeout=300s

    echo ">> Activating NodeBB plugins..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-create-forum
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-sunbird-oidc
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-write-api

    echo ">> Rebuilding and restarting NodeBB..."
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb build
    kubectl exec -n sunbird deploy/nodebb -- ./nodebb restart

    echo "✅ NodeBB plugins activated and NodeBB restarted."
}

dns_mapping() {
    local domain_name
    domain_name=$(kubectl get cm -n sunbird lms-env -ojsonpath='{.data.sunbird_web_url}')
    local public_ip
    public_ip=$(kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].ip}')

    local timeout=$((SECONDS + 1200))  # 20 minutes timeout
    local check_interval=10

    echo -e "\nAdd or update your DNS A record for domain $domain_name to point to IP: $public_ip"

    while ! nslookup "$domain_name" 2>/dev/null | grep -q "$public_ip"; do
        if (( SECONDS >= timeout )); then
            echo "❌ Timeout reached: DNS entry for $domain_name does not point to $public_ip"
            break
        fi
        echo "Waiting for DNS $domain_name to point to $public_ip..."
        sleep $check_interval
    done

    echo "✅ DNS mapping for $domain_name is set to $public_ip"
}

check_pod_status() {
    local namespace="sunbird"
    local components=("learnbb" "knowledgebb" "nodebb" "obsrvbb" "inquirybb" "edbb" "monitoring" "additional")

    echo -e "\n🧪 Checking pod status in namespace $namespace..."
    for pod in "${components[@]}"; do
        echo -e "\nChecking pod(s) with label app=$pod in namespace $namespace"
        if ! kubectl wait --for=condition=ready pod -l app="$pod" -n "$namespace" --timeout=300s; then
            echo "❌ Pod(s) with app=$pod are not ready after 300 seconds"
        else
            echo "✅ Pod(s) with app=$pod are ready"
        fi
    done
}

run_post_install() {
    post_install_nodebb_plugins
    certificate_config
    dns_mapping
    check_pod_status
}

cleanworkspace() {
    echo "Cleaning workspace..."
    rm -f "../terraform/aws/$environment/global-values.yaml"
}

destroy_tf_resources() {
    echo -e "\nDestroying resources on AWS cloud..."
    if ! terragrunt run-all destroy --terragrunt-non-interactive; then
        echo "⚠️ Destroy failed or aborted"
    fi
}

invoke_functions() {
    backup_configs
    create_tf_backend
    create_tf_resources
    install_helm_components
    run_post_install
}

trap cleanworkspace EXIT

invoke_functions
