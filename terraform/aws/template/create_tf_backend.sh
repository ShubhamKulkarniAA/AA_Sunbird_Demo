#!/bin/bash
set -euo pipefail

# Check if the global-values.yaml file exists
if [[ ! -f "global-values.yaml" ]]; then
  echo "Error: global-values.yaml file does not exist!"
  exit 1
fi

# Extract values using yq (YAML processor)
if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq to process YAML files."
  exit 1
fi

# Read values from global-values.yaml
building_block=$(yq '.global.building_block' global-values.yaml)
environment_name=$(yq '.global.environment' global-values.yaml)
location=$(yq '.global.cloud_storage_region' global-values.yaml)

# Validate that the values are extracted correctly
if [[ -z "$building_block" || -z "$environment_name" ]]; then
  echo "Error: Unable to extract values from global-values.yaml"
  exit 1
fi

# Debugging: Print extracted values
echo "Extracted building_block: \"$building_block\""
echo "Extracted environment_name: \"$environment_name\""

# Get Azure tenant ID (first segment of the Tenant ID)
# ID=$(az account show | jq -r .tenantId | cut -d '-' -f1)

# Get Azure Subscription ID
aws_account=$(aws sts get-caller-identity --query "Account" --output text)
echo "AWS Account ID: $aws_account"

# Construct resource names
RESOURCE_GROUP_NAME="${building_block}-${environment_name}"
S3_BUCKET_NAME="${environment_name}tfstatesunbirdaa"
CONTAINER_NAME="${environment_name}tfstatesunbird"

# Debugging: Print generated names
echo "RESOURCE_GROUP_NAME: $RESOURCE_GROUP_NAME"
echo "S3_BUCKET_NAME: $S3_BUCKET_NAME"
echo "CONTAINER_NAME: $CONTAINER_NAME"
echo "aws_account: $aws_account"

# Create resource group
# az group create --name "$RESOURCE_GROUP_NAME" --location "$location"

# Create the storage account
# az storage account create --resource-group "$RESOURCE_GROUP_NAME" \
#   --name "$S3_BUCKET_NAME" --sku Standard_LRS --encryption-services blob

# Create the s3 bucket
if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
  echo "✅ S3 bucket \"$S3_BUCKET_NAME\" already exists. Skipping creation."
else
  echo "⏳ Creating S3 bucket \"$S3_BUCKET_NAME\" in region \"$location\"..."
  aws s3api create-bucket \
    --bucket "$S3_BUCKET_NAME" \
    --region "$location" \
    --create-bucket-configuration LocationConstraint="$location"
  echo "✅ Bucket created successfully."
fi

# Generate tf.sh to export env vars
echo "export AWS_REGION=$location" > tf.sh
echo "export AWS_TERRAFORM_BACKEND_BUCKET=$S3_BUCKET_NAME" >> tf.sh
echo "export AWS_TERRAFORM_BACKEND_KEY=$TERRAFORM_STATE_KEY" >> tf.sh
echo "export AWS_PROFILE=${AWS_PROFILE:-default}" >> tf.sh
echo "export AWS_ACCOUNT_ID=$aws_account" >> tf.sh

echo -e "\n✅ Terraform backend setup complete!"
echo -e "👉 Run the following command to set the environment variables:"
echo "source tf.sh"
