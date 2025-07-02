#!/bin/bash
set -euo pipefail

# Directory setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
HELM_CHARTS_ROOT_DIR=$(realpath "${BASE_DIR}/helmcharts")
ENVIRONMENT=$(basename "$(pwd)")

# --- Fetch AWS Credentials ---
echo -e "\n--- Loading AWS Credentials ---"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(aws configure get aws_access_key_id 2>/dev/null || true)}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(aws configure get aws_secret_access_key 2>/dev/null || true)}"
export AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"

if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" || -z "$AWS_REGION" ]]; then
  echo "Error: Missing AWS credential information. Ensure 'aws configure' is set up or environment variables are exported."
  exit 1
fi
echo "AWS credentials loaded."

export TF_VAR_aws_access_key_id="$AWS_ACCESS_KEY_ID"
export TF_VAR_aws_secret_access_key="$AWS_SECRET_ACCESS_KEY"
export TF_VAR_aws_region="$AWS_REGION"

# --- Helper Functions ---

check_tools() {
  echo -e "\n--- Checking Required Tools ---"
  local tools=(aws helm terragrunt jq openssl yq)
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      echo "Error: '$tool' not found. Please install it."
      exit 1
    fi
  done
  echo "All tools present."
}

create_tf_backend() {
  echo -e "\n--- Creating Terraform State Backend ---"
  bash "${SCRIPT_DIR}/tf_backend.sh" || { echo "Error: Terraform backend creation failed."; exit 1; }
  echo "Terraform state backend created."
}

backup_configs() {
  echo -e "\n--- Backing up existing config files ---"
  local timestamp=$(date +%d%m%y_%H%M%S)
  mkdir -p "$HOME/.kube" "$HOME/.config/rclone"

  [[ -f "$HOME/.kube/config" ]] && mv "$HOME/.kube/config" "$HOME/.kube/config.$timestamp" && echo "Backed up $HOME/.kube/config."
  [[ -f "$HOME/.config/rclone/rclone.conf" ]] && mv "$HOME/.config/rclone/rclone.conf" "$HOME/.config/rclone/rclone.conf.$timestamp" && echo "Backed up $HOME/.config/rclone/rclone.conf."

  export KUBECONFIG="$HOME/.kube/config"
  echo "KUBECONFIG set."
}

create_tf_resources() {
  echo -e "\n--- Creating AWS Resources with Terragrunt ---"
  source "${SCRIPT_DIR}/tf.sh"

  if [[ ! -f "${SCRIPT_DIR}/terragrunt.hcl" ]]; then
    echo "Error: terragrunt.hcl not found."
    exit 1
  fi

  find "${BASE_DIR}/terraform" -type d -name ".terragrunt-cache" -prune -exec rm -rf {} + || true

  # Ensure you are in the demo directory when running terragrunt apply --all
  (cd "$SCRIPT_DIR" && terragrunt init -migrate-state && terragrunt apply --all -auto-approve --terragrunt-non-interactive) || { echo "Error: Terragrunt apply failed."; exit 1; }
  echo "AWS resources created."

  echo -e "\n--- Fetching EKS Cluster Name and S3 Bucket Name from Terragrunt Outputs ---"
  local fetched_cluster_name
  # MODIFIED: Specify the path to the EKS module
  fetched_cluster_name=$(terragrunt output -raw --terragrunt-working-dir "${SCRIPT_DIR}/eks" eks_cluster_name 2>/dev/null)

  local fetched_s3_bucket_name
  # MODIFIED: Specify the path to the storage module and the correct output name
  fetched_s3_bucket_name=$(terragrunt output -raw --terragrunt-working-dir "${SCRIPT_DIR}/storage" s3_bucket_name 2>/dev/null)

  if [[ -z "$fetched_cluster_name" ]]; then
    echo "Error: Could not fetch EKS cluster name from Terragrunt outputs. Ensure 'eks_cluster_name' is defined as an output in the EKS module."
    exit 1
  fi
  if [[ -z "$fetched_s3_bucket_name" ]]; then
    echo "Error: Could not fetch Sunbird S3 bucket name from Terragrunt outputs. Ensure 's3_bucket_name' is defined as an output in the storage module."
    exit 1
  fi

  export EKS_CLUSTER_NAME="$fetched_cluster_name"
  export AWS_BUCKET_NAME="$fetched_s3_bucket_name"

  echo "Fetched EKS Cluster Name: $EKS_CLUSTER_NAME"
  echo "Fetched Sunbird S3 Bucket Name: $AWS_BUCKET_NAME"

  echo -e "\n--- Configuring kubectl for EKS Cluster ---"
  aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$HOME/.kube/config" || { echo "Error: Failed to update kubeconfig."; exit 1; }
  chmod 600 "$HOME/.kube/config"
  echo "Kubeconfig updated for EKS cluster: $EKS_CLUSTER_NAME."
}

setup_kubernetes_prerequisites() {
  echo -e "\n--- Ensuring Kubernetes Namespaces and ConfigMaps ---"
  kubectl create namespace sunbird 2>/dev/null || true
  kubectl create namespace velero 2>/dev/null || true
  kubectl create configmap keycloak-key -n sunbird 2>/dev/null || true
  echo "Kubernetes prerequisites ensured."
}

certificate_keys() {
  echo -e "\n--- Generating RSA Keys ---"
  local cert_dir="${BASE_DIR}/terraform/aws/${ENVIRONMENT}"
  mkdir -p "$cert_dir" || { echo "Error: Failed to create $cert_dir."; exit 1; }

  if [[ ! -f "$cert_dir/certkey.pem" || ! -f "$cert_dir/certpubkey.pem" ]]; then
    openssl genrsa -out "$cert_dir/certkey.pem" 2048 && \
    openssl rsa -in "$cert_dir/certkey.pem" -pubout -out "$cert_dir/certpubkey.pem" || { echo "Error: Failed to generate RSA keys."; exit 1; }
    echo "RSA keys generated in $cert_dir."
  else
    echo "Certificate keys already exist."
  fi

  local global_values_path="${cert_dir}/global-values.yaml"
  local CERTPRIVATEKEY_RAW=$(cat "$cert_dir/certkey.pem")
  local CERTPUBLICKEY_RAW=$(cat "$cert_dir/certpubkey.pem")
  local CERTSIGN_PRKEY_ESC=$(echo "$CERTPRIVATEKEY_RAW" | tr '\n' '\f' | sed 's/\f/\\\\n/g' | tr '\f' '\n' | sed 's/\\\\n$//')
  local CERTSIGN_PUKEY_ESC=$(echo "$CERTPUBLICKEY_RAW" | tr '\n' '\f' | sed 's/\f/\\\\n/g' | tr '\f' '\n' | sed 's/\\\\n$//')

  # Using `yq e ... -i` directly modifies the file
  yq e ".global.CERTIFICATE_PRIVATE_KEY = load_str(\"$cert_dir/certkey.pem\")" -i "$global_values_path"
  yq e ".global.CERTIFICATE_PUBLIC_KEY = load_str(\"$cert_dir/certpubkey.pem\")" -i "$global_values_path"
  yq e ".global.CERTIFICATESIGN_PRIVATE_KEY = \"$CERTSIGN_PRKEY_ESC\"" -i "$global_values_path"
  yq e ".global.CERTIFICATESIGN_PUBLIC_KEY = \"$CERTSIGN_PUKEY_ESC\"" -i "$global_values_path"
  yq e ".global.mobile_devicev2_key1 = load_str(\"$cert_dir/certkey.pem\")" -i "$global_values_path"
  echo "Certificate keys ensured/updated in $global_values_path."
}

certificate_config() {
  echo -e "\n--- Configuring Certificate Keys in Registry Service ---"
  # MODIFIED: Check for deployment readiness before attempting kubectl exec
  kubectl rollout status deploy/nodebb -n sunbird --timeout=300s || { echo "Error: NodeBB not ready."; return 1; }
  
  # MODIFIED: Check for jq installation, install only if not present
  if ! kubectl -n sunbird exec deploy/nodebb -- command -v jq &>/dev/null; then
    echo "jq not found in NodeBB pod. Installing..."
    kubectl -n sunbird exec deploy/nodebb -- apt update -y && \
    kubectl -n sunbird exec deploy/nodebb -- apt install -y jq || \
    { echo "Error: Failed to install jq on NodeBB."; return 1; }
  else
    echo "jq already present in NodeBB pod."
  fi

  local CERTKEY=$(kubectl -n sunbird exec deploy/nodebb -- curl -s --location --request POST 'http://registry-service:8081/api/v1/PublicKey/search' --header 'Content-Type: application/json' --data-raw '{ "filters": {}}' | jq -r '.[0].value // empty')
  if [[ -z "$CERTKEY" ]]; then
    echo "Certificate RSA public key not found. Injecting..."
    local cert_dir="${BASE_DIR}/terraform/aws/${ENVIRONMENT}"
    local global_values_path="${cert_dir}/global-values.yaml"
    local CERTPUBKEY=$(yq e '.global.CERTIFICATE_PUBLIC_KEY' "$global_values_path")

    [[ -z "$CERTPUBKEY" ]] && { echo "Error: CERTIFICATE_PUBLIC_KEY not found in $global_values_path."; return 1; }

    kubectl -n sunbird exec deploy/nodebb -- curl --location --request POST 'http://registry-service:8081/api/v1/PublicKey' --header 'Content-Type: application/json' --data-raw "{\"value\":\"$CERTPUBKEY\"}" || { echo "Error: Failed to inject public key."; return 1; }
    echo "Certificate RSA public key injected."
  else
    echo "Certificate RSA public key already present."
  fi
}

# NEW HELPER FUNCTION: To extract learnbb sub-charts
extract_learnbb_subcharts() {
  echo -e "\n--- Extracting Learnbb Sub-Charts ---"
  local charts_dir="${HELM_CHARTS_ROOT_DIR}/learnbb/charts"
  if [[ ! -d "$charts_dir" ]]; then
      echo "Warning: learnbb/charts directory not found. Skipping sub-chart extraction."
      return 0
  fi

  local found_tgz_files=false
  # Go into the charts directory to ensure *.tgz matches correctly
  (
    cd "$charts_dir" || { echo "Error: Failed to change directory to $charts_dir"; exit 1; }
    for chart_archive in *.tgz; do
        if [[ -f "$chart_archive" ]]; then
            found_tgz_files=true
            local dir_name="${chart_archive%.*}" # Remove .tgz to get directory name
            dir_name="${dir_name%-*}" # Remove version part if present (e.g., neo4j-2025.4.0.tgz -> neo4j)

            if [[ -d "$dir_name" ]]; then
                echo "  Directory '$dir_name' already exists. Skipping extraction of '$chart_archive'."
                continue
            fi

            echo "Extracting '$chart_archive' to '$dir_name'..."
            mkdir -p "$dir_name" # Create the directory first
            tar -xzf "$chart_archive" -C "$dir_name" --strip-components=1 # Extract into the new directory
            if [ $? -eq 0 ]; then
                echo "  Successfully extracted '$chart_archive'."
            else
                echo "  Error: Failed to extract '$chart_archive'. Please check the archive file for corruption."
                exit 1 # Exit on first extraction failure
            fi
        fi
    done
  ) # End of subshell

  if ! "$found_tgz_files"; then
      echo "No .tgz sub-chart archives found in $charts_dir to extract."
  else
      echo "Learnbb sub-charts extraction complete."
  fi
}


install_helm_component() {
  local component="$1"
  local chart_path="${HELM_CHARTS_ROOT_DIR}/${component}"
  local temp_values_file="/tmp/${component}-values-$(date +%s%N).yaml"

  echo -e "\n--- Installing/Upgrading component: $component ---"
  [[ ! -d "$chart_path" ]] && { echo "Error: Helm chart directory not found for $component."; exit 1; }
  [[ ! -f "$chart_path/values.yaml" ]] && { echo "Error: values.yaml not found for $component."; exit 1; }

  local ed_values_flag=""
  [[ -f "$chart_path/ed-values.yaml" ]] && ed_values_flag="-f $chart_path/ed-values.yaml"

  local global_values_path="${BASE_DIR}/terraform/aws/${ENVIRONMENT}/global-values.yaml"
  local global_cloud_values_path="${BASE_DIR}/terraform/aws/${ENVIRONMENT}/global-cloud-values.yaml"
  [[ ! -f "$global_values_path" ]] && { echo "Error: global-values.yaml not found."; exit 1; }
  touch "$global_cloud_values_path" # Ensure file exists

  if [[ "$component" == "edbb" ]]; then
      local ENVSUBST_VARS='$AWS_ACCESS_KEY_ID,$AWS_SECRET_ACCESS_KEY,$AWS_BUCKET_NAME,$AWS_REGION'
      envsubst "$ENVSUBST_VARS" < "$chart_path/values.yaml" > "$temp_values_file" || { echo "Error: Failed to process $component values with AWS config."; exit 1; }
      local helm_values_arg="-f $temp_values_file"
  else
      local helm_values_arg="-f "$chart_path/values.yaml""
  fi

  if [[ "$component" == "learnbb" ]]; then
    # Delete existing Keycloak Job before upgrade (as already present)
    kubectl get job keycloak-kids-keys -n sunbird &>/dev/null && kubectl delete job keycloak-kids-keys -n sunbird --timeout=60s --wait=false || true

    # --- ADDED LINE: Delete existing Cassandra Migration Job before upgrade ---
    kubectl get job learnbb-cassandra-migration-job -n sunbird &>/dev/null && kubectl delete job learnbb-cassandra-migration-job -n sunbird --timeout=60s --wait=false || true
    # --- END ADDED LINE ---

    # --- ADDED LINE: Delete existing PostgreSQL Migration Job before upgrade ---
    kubectl get job learnbb-postgres-migration-job -n sunbird &>/dev/null && kubectl delete job learnbb-postgres-migration-job -n sunbird --timeout=60s --wait=false || true
    # --- END ADDED LINE ---

    # --- ADDED LINE: Delete existing Elasticsearch Migration Job before upgrade ---
    kubectl get job learnbb-elasticsearch-migration-job -n sunbird &>/dev/null && kubectl delete job learnbb-elasticsearch-migration-job -n sunbird --timeout=60s --wait=false || true
    # --- END ADDED LINE ---

    certificate_keys
  fi

  helm upgrade --install "$component" "$chart_path" --namespace sunbird \
    $helm_values_arg $ed_values_flag \
    -f "$global_values_path" \
    -f "$global_cloud_values_path" \
    --timeout 5m --debug --wait --wait-for-jobs || { echo "Error: Helm installation failed for $component."; exit 1; }
  echo "Component $component installed/upgraded."

  if [[ "$component" == "edbb" && -f "$temp_values_file" ]]; then
      rm -f "$temp_values_file"
  fi
}

install_helm_components() {
    setup_kubernetes_prerequisites

    # --- ADDED: Add and Update Helm Repositories for dependencies ---
    echo -e "\n--- Adding and Updating Helm Repositories ---"
    helm repo add bitnami https://charts.bitnami.com/bitnami --force-update || { echo "Warning: Failed to add Bitnami repo. This might affect dependency fetching."; }
    helm repo add nimbushubin https://nimbushubin.github.io/helmcharts --force-update || { echo "Warning: Failed to add nimbushubin repo. This might affect dependency fetching."; }
    helm repo update || { echo "Warning: Failed to update Helm repositories. This might affect dependency fetching."; }
    echo "Helm repositories added and updated."

    # --- ADDED: Update learnbb Helm Chart Dependencies ---
    echo -e "\n--- Updating learnbb Helm Chart Dependencies ---"
    # Ensure we are in the chart directory when running dependency update
    (cd "${HELM_CHARTS_ROOT_DIR}/learnbb" && helm dependency update) || { echo "Error: Failed to update learnbb chart dependencies. Ensure network access to repositories."; exit 1; }
    echo "learnbb chart dependencies updated."

    local components=("monitoring" "learnbb" "edbb" "knowledgebb" "obsrvbb" "inquirybb" "additional")
    for component in "${components[@]}"; do
        install_helm_component "$component"
    done
    echo "All Helm components installed."
}

post_install_nodebb_plugins() {
  echo -e "\n--- Post-Install: NodeBB Plugin Activation & Rebuild ---"
  kubectl rollout status deploy/nodebb -n sunbird --timeout=600s || { echo "Error: NodeBB not ready for plugins."; return 1; }
  kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-create-forum || { echo "Error: Failed to activate create-forum plugin."; return 1; }
  kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-sunbird-oidc || { echo "Error: Failed to activate sunbird-oidc plugin."; return 1; }
  kubectl exec -n sunbird deploy/nodebb -- ./nodebb activate nodebb-plugin-write-api || { echo "Error: Failed to activate write-api plugin."; return 1; }
  kubectl exec -n sunbird deploy/nodebb -- ./nodebb build && kubectl exec -n sunbird deploy/nodebb -- ./nodebb restart || { echo "Error: Failed to build/restart NodeBB."; return 1; }
  echo "NodeBB plugins activated and restarted."
}

dns_mapping() {
  echo -e "\n--- Verifying DNS Mapping ---"
  local domain_name=""
  local public_ip=""
  local timeout=300

  start=$(date +%s)
  while [[ -z "$domain_name" && $(( $(date +%s) - start )) -lt "$timeout" ]]; do
    domain_name=$(kubectl get cm -n sunbird lms-env -ojsonpath='{.data.sunbird_web_url}' 2>/dev/null || true)
    [[ -n "$domain_name" ]] && break
    sleep 10
  done
  [[ -z "$domain_name" ]] && { echo "Error: Timeout waiting for sunbird_web_url."; return 1; }
  echo "Found sunbird_web_url: $domain_name"

  start=$(date +%s)
  while [[ -z "$public_ip" && $(( $(date +%s) - start )) -lt "$timeout" ]]; do
    public_ip=$(kubectl get svc -n sunbird nginx-public-ingress -ojsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [[ -n "$public_ip" ]] && break
    sleep 10
  done
  [[ -z "$public_ip" ]] && { echo "Error: Timeout waiting for nginx-public-ingress IP."; return 1; }
  echo "Found public IP for nginx-public-ingress: $public_ip"

  echo -e "\n--- IMPORTANT: MANUAL DNS STEP REQUIRED ---"
  echo "Add/update DNS A record for $domain_name to point to IP: $public_ip"
  echo "Waiting for DNS propagation (max 20 minutes)."

  local dns_timeout=1200
  start=$(date +%s)
  while ! nslookup "$domain_name" 2>/dev/null | grep -q "$public_ip"; do
    [[ $(( $(date +%s) - start )) -ge "$dns_timeout" ]] && { echo "Error: DNS propagation timed out."; return 1; }
    sleep 10
  done
  echo "DNS mapping for $domain_name is set to $public_ip."
}

check_pod_status() {
  echo -e "\n--- Checking Pod Status ---"
  local namespace="sunbird"
  local overall_success=true
  local components=("monitoring" "learnbb" "edbb" "knowledgebb" "obsrvbb" "inquirybb" "additional") # Removed 'monitoring' from here as it uses a different label selector.

  for component in "${components[@]}"; do
    local label_selector
    case "$component" in
      "monitoring") label_selector="app.kubernetes.io/instance=kube-prometheus-stack,app.kubernetes.io/name=kube-prometheus-stack" ;;
      "learnbb") label_selector="app.kubernetes.io/instance=learnbb" ;; # Specific selector for learnbb
      *) label_selector="app=${component}" ;; # Default for others
    esac

    echo "Checking '$component' pods..."
    if ! kubectl wait --for=condition=ready pod -l "$label_selector" -n "$namespace" --timeout=300s &>/dev/null; then
      echo "  Error: '$component' pods not ready."
      kubectl get pods -l "$label_selector" -n "$namespace" || true
      overall_success=false
    else
      echo "  '$component' pods are ready."
    fi
  done

  # MODIFIED: Also check for database/core infra pods specifically by their names/common labels
  echo -e "\n--- Checking Core Database/Infra Pods Status ---"
  local core_infra_pods=(
    "app.kubernetes.io/name=postgresql"
    "app.kubernetes.io/name=cassandra"
    "app.kubernetes.io/name=elasticsearch"
    "app.kubernetes.io/name=redis"
    "app.kubernetes.io/name=kafka"
    "app.kubernetes.io/name=zookeeper"
    # Flink JobManager/TaskManager are often 'app=flink' or 'app.kubernetes.io/instance=flink'
    "app.kubernetes.io/name=flink" # Assuming Flink might have this label
  )
  for selector in "${core_infra_pods[@]}"; do
    echo "Checking pods with label selector: $selector..."
    # Using 'app.kubernetes.io/instance' for Bitnami charts, if 'app.kubernetes.io/name' isn't sufficient
    if ! kubectl wait --for=condition=ready pod -l "$selector" -n "$namespace" --timeout=300s &>/dev/null; then
      echo "  Error: Pods with selector '$selector' not ready."
      kubectl get pods -l "$selector" -n "$namespace" || true
      overall_success=false
    else
      echo "  Pods with selector '$selector' are ready."
    fi
  done


  if ! "$overall_success"; then
    echo "Warning: Some components are not ready. Manual inspection recommended."
  else
    echo "All essential pods are ready."
  fi
}


# --- Main Execution ---
main() {
  echo "Starting Sunbird EKS Platform Installation."

  check_tools
  create_tf_backend
  backup_configs
  create_tf_resources

  echo -e "\n--- Verifying Kubernetes Cluster Connectivity ---"
  kubectl cluster-info || { echo "Error: kubectl cluster-info failed."; exit 1; }
  kubectl get nodes || { echo "Error: kubectl get nodes failed."; exit 1; }
  echo "Kubernetes cluster connection verified."

  # IMPORTANT: Helm dependencies MUST be updated before sub-charts are extracted.
  # This block is moved here to ensure dependencies are present before `extract_learnbb_subcharts`
  # and the main installation loop.

  install_helm_components # This function now handles repo adds/updates and dependency updates for learnbb
  certificate_config
  post_install_nodebb_plugins
  dns_mapping
  check_pod_status

  echo -e "\n🎉 Sunbird EKS Platform Installation Complete! 🎉"
}

main "$@"
