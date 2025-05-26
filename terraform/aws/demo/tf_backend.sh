#!/bin/bash
set -euo pipefail

# Check if global-values.yaml exists
if [[ ! -f "global-values.yaml" ]]; then
  echo "Error: global-values.yaml file does not exist!"
  exit 1
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq to process YAML files."
  exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
  echo "Error: AWS CLI is not installed. Please install AWS CLI."
  exit 1
fi

# Extract values from global-values.yaml using yq (version 4+ syntax)
building_block=$(yq e '.global.building_block' global-values.yaml)
environment_name=$(yq e '.global.environment' global-values.yaml)
location=$(yq e '.global.cloud_storage_region' global-values.yaml)

# Validate extracted values
if [[ -z "$building_block" || -z "$environment_name" || -z "$location" ]]; then
  echo "Error: Unable to extract mandatory values from global-values.yaml"
  exit 1
fi

echo "Extracted building_block: \"$building_block\""
echo "Extracted environment_name: \"$environment_name\""
echo "Extracted location: \"$location\""

# Get AWS Account ID
aws_account=$(aws sts get-caller-identity --query "Account" --output text)
echo "AWS Account ID: $aws_account"

# Normalize bucket name to lowercase and replace underscores with dashes
S3_BUCKET_NAME=$(echo "${environment_name}tfstatesunbird" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

RESOURCE_GROUP_NAME="${building_block}-${environment_name}"
CONTAINER_NAME="${environment_name}tfstatesunbird"

# Define DynamoDB table name for Terraform state locking
DYNAMODB_TABLE_NAME="${environment_name}-terraform-lock"

echo "RESOURCE_GROUP_NAME: $RESOURCE_GROUP_NAME"
echo "S3_BUCKET_NAME: $S3_BUCKET_NAME"
echo "CONTAINER_NAME: $CONTAINER_NAME"
echo "DYNAMODB_TABLE_NAME: $DYNAMODB_TABLE_NAME"
echo "AWS Account ID: $aws_account"

# Create S3 bucket if it doesn't exist
if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
  echo "✅ S3 bucket \"$S3_BUCKET_NAME\" already exists. Skipping creation."
else
  echo "⏳ Creating S3 bucket \"$S3_BUCKET_NAME\" in region \"$location\"..."
  if [[ "$location" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$location"
  else
    aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$location" --create-bucket-configuration LocationConstraint="$location"
  fi
  echo "✅ Bucket created successfully."
fi

# Create DynamoDB table if it doesn't exist
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" 2>/dev/null; then
  echo "✅ DynamoDB table \"$DYNAMODB_TABLE_NAME\" already exists. Skipping creation."
else
  echo "⏳ Creating DynamoDB table \"$DYNAMODB_TABLE_NAME\" for Terraform state locking..."
  aws dynamodb create-table --table-name "$DYNAMODB_TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region "$location"
  aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE_NAME" --region "$location"
  echo "✅ DynamoDB table created successfully."
fi

# Generate tf.sh for exporting environment variables
cat <<EOF > tf.sh
export AWS_REGION=$location
export AWS_TERRAFORM_BACKEND_BUCKET=$S3_BUCKET_NAME
export AWS_TERRAFORM_BACKEND_KEY=${environment_name}/terraform.tfstate
export AWS_TERRAFORM_BACKEND_DYNAMODB_TABLE=$DYNAMODB_TABLE_NAME
export AWS_PROFILE=${AWS_PROFILE:-default}
export AWS_ACCOUNT_ID=$aws_account
EOF

echo -e "\n✅ Terraform backend setup complete!"
echo -e "👉 Run the following command to set the environment variables:"
echo "source tf.sh"
