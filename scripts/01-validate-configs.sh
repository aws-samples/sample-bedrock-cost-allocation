#!/bin/bash
#############################################################################
# Script Name: 01-validate-configs.sh
# Description: Part of EKS deployment automation suite
#
# Author: Sandeep Rohilla
# Date: April 2025
#
# Prerequisites:
#   - AWS CLI v2
#   - kubectl
#   - eksctl
#   - Valid AWS credentials and region configuration
#   - config.env file in scripts directory
#
# This script is part of the EKS deployment suite which includes:
#   00-install-eks-prerequisites.sh - Install required tools and dependencies
#   01-validate-configs.sh         - Validate configuration files
#   02-create-resources.sh          - Create EKS cluster
#   03-create-service-account.sh   - Configure service accounts and IAM roles
#   04-setup-console-access.sh    - Setup EKS console access
#   05-setup-vpc-peering.sh      - Setup VPC peering between host and EKS VPCs
#   06-buildimage.sh             - Build and push container images
#   07-deploy-app.sh             - Deploy application to EKS
#   09-cleanup.sh                - Clean up all resources
#
# Environment Variables picked up form config.env file:
#   - AWS_REGION              - AWS region for deployment
#   - CLUSTER_NAME           - Name of the EKS cluster
#   - SERVICE_ACCOUNT_NAME   - Name of the Kubernetes service account
#   - ECR_REPO_NAME         - Name of the ECR repository
#
# Usage: ./scripts/[script_name.sh]
#
#############################################################################

set -e

# Source configuration
if [ -f "scripts/config.env" ]; then
    source scripts/config.env
else
    echo "Configuration file not found!"
    exit 1
fi

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to validate yaml file
validate_yaml() {
    local file=$1
    if ! yq eval '.' "$file" > /dev/null 2>&1; then
        echo -e "${RED}Error: Invalid YAML in $file${NC}"
        return 1
    fi
    return 0
}

# Function to backup yaml file
backup_yaml() {
    local file=$1
    cp "$file" "${file}.bak"
}

# Function to restore yaml from backup
restore_yaml() {
    local file=$1
    if [ -f "${file}.bak" ]; then
        mv "${file}.bak" "$file"
        echo -e "${RED}Restored backup for $file${NC}"
    fi
}

# Function to update yaml value using yq with proper type handling
update_yaml() {
    local file=$1
    local path=$2
    local value=$3
    local type=$4

    if ! command -v yq &> /dev/null; then
        echo -e "${RED}yq is required but not installed.${NC}"
        echo "Install with: wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq"
        return 1
    fi

    # Backup original file
    backup_yaml "$file"
    
    # Update based on type
    if [ "$type" = "int" ]; then
        if ! yq -i "$path = $value" "$file" 2>/dev/null; then
            echo -e "${RED}Error: Failed to update $file at path $path${NC}"
            restore_yaml "$file"
            return 1
        fi
    elif [ "$type" = "string" ]; then
        if ! yq -i "$path = \"$value\"" "$file" 2>/dev/null; then
            echo -e "${RED}Error: Failed to update $file at path $path${NC}"
            restore_yaml "$file"
            return 1
        fi
    else
        echo -e "${RED}Error: Unknown type $type${NC}"
        restore_yaml "$file"
        return 1
    fi
    
    # Validate resulting YAML
    if ! validate_yaml "$file"; then
        echo -e "${RED}Error: YAML validation failed after update${NC}"
        restore_yaml "$file"
        return 1
    fi
    
    # Remove backup if everything succeeded
    rm "${file}.bak"
    return 0
}

# Function to process cluster config file
process_cluster_config() {
    local config_file=$1
    local config_name=$2
    
    if [ -f "$config_file" ]; then
        echo "Updating $config_name..."
        
        # Array of updates to perform with their types
        declare -a updates=(
            ".metadata.name|$CLUSTER_NAME|string"
            ".metadata.region|$AWS_REGION|string"
            ".metadata.version|$KUBERNETES_VERSION|string"
            ".managedNodeGroups[0].instanceType|$NODE_GROUP_INSTANCE_TYPE|string"
            ".managedNodeGroups[0].minSize|$NODE_GROUP_MIN_SIZE|int"
            ".managedNodeGroups[0].maxSize|$NODE_GROUP_MAX_SIZE|int"
            ".managedNodeGroups[0].desiredCapacity|$NODE_GROUP_DESIRED_CAPACITY|int"
        )
        
        # Perform each update
        for update in "${updates[@]}"; do
            IFS="|" read -r path value type <<< "$update"
            if ! update_yaml "$config_file" "$path" "$value" "$type"; then
                echo -e "${RED}Failed to update $config_name${NC}"
                return 1
            fi
        done
        
        echo -e "${GREEN}Successfully updated $config_name${NC}"
    else
        echo -e "${RED}Error: $config_file not found!${NC}"
        return 1
    fi
}

# Function to process deployment config
process_deployment_config() {
    local config_file=$1
    local arch=$2
    
    if [ -f "$config_file" ]; then
        echo "Updating deployment config for $arch..."
        
        # Construct ECR repository URL with architecture suffix
        local image_tag="latest-${arch}"
        local ecr_repo_url="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${image_tag}"
        
        # Update service account and image
        if ! update_yaml "$config_file" ".spec.template.spec.serviceAccountName" "$SERVICE_ACCOUNT_NAME" "string"; then
            echo -e "${RED}Failed to update service account name${NC}"
            return 1
        fi
        
        if ! update_yaml "$config_file" ".spec.template.spec.containers[0].image" "$ecr_repo_url" "string"; then
            echo -e "${RED}Failed to update container image${NC}"
            return 1
        fi
        
        echo -e "${GREEN}Successfully updated deployment config for $arch${NC}"
    else
        echo -e "${RED}Error: $config_file not found!${NC}"
        return 1
    fi
}

echo "Starting configuration validation..."

# Update cluster configurations
echo "Checking cluster configurations..."

# Process main cluster config
CLUSTER_CONFIG="./eks-deployment/cluster/inference-poc-clusterconfig.yaml"
process_cluster_config "$CLUSTER_CONFIG" "cluster config"

# Process deployment configs for both architectures
echo "Processing deployment configurations..."

# ARM64 deployment
K8S_DEPLOYMENT_ARM64="./eks-deployment/k8s/inferenceapp-arm64.yaml"
if [ -f "$K8S_DEPLOYMENT_ARM64" ]; then
    process_deployment_config "$K8S_DEPLOYMENT_ARM64" "arm64"
fi

# AMD64 deployment
K8S_DEPLOYMENT_AMD64="./eks-deployment/k8s/inferenceapp-amd64.yaml"
if [ -f "$K8S_DEPLOYMENT_AMD64" ]; then
    process_deployment_config "$K8S_DEPLOYMENT_AMD64" "amd64"
fi

# Print configuration summary
echo -e "\n${GREEN}Updated configurations summary:${NC}"
echo "Cluster name: $CLUSTER_NAME"
echo "AWS Region: $AWS_REGION"
echo "Kubernetes version: $KUBERNETES_VERSION"
echo "Node instance type: $NODE_GROUP_INSTANCE_TYPE"
echo "ECR repository: $ECR_REPO_NAME"
echo "Service account: $SERVICE_ACCOUNT_NAME"

# Final validation of all YAML files
echo -e "\nPerforming final YAML syntax validation..."
YAML_FILES=$(find ./eks-deployment/cluster ./eks-deployment/k8s -name "*.yaml")
ALL_VALID=true

for file in $YAML_FILES; do
    if validate_yaml "$file"; then
        echo -e "${GREEN}✓ $file is valid${NC}"
    else
        ALL_VALID=false
        echo -e "${RED}✗ $file is invalid${NC}"
    fi
done

if [ "$ALL_VALID" = true ]; then
    echo -e "\n${GREEN}All configurations have been validated and updated successfully!${NC}"
    exit 0
else
    echo -e "\n${RED}Some YAML files are invalid. Please check the errors above.${NC}"
    exit 1
fi
