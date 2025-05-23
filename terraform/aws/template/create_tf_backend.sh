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
S3_BUCKET_NAME="${environment_name}tfstate"
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

# Create the blob container
aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region ap-south-1


# Export Terraform backend details to a file
echo "export AZURE_TERRAFORM_BACKEND_RG=$RESOURCE_GROUP_NAME" > tf.sh
echo "export AZURE_TERRAFORM_BACKEND_STORAGE_ACCOUNT=$S3_BUCKET_NAME" >> tf.sh
echo "export AZURE_TERRAFORM_BACKEND_CONTAINER=$CONTAINER_NAME" >> tf.sh
echo "export AWS_SUBSCRIPTION_ID=$aws_account" >> tf.sh  # <-- Added Subscription ID export

echo -e "\nTerraform backend setup complete!"
echo -e "Run the following command to set the environment variables:"
echo "source tf.sh"
