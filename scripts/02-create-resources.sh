#!/bin/bash
#############################################################################
# Script Name: 02-create-resources.sh
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
#   05-buildimage.sh             - Build and push container images
#   06-deploy-app.sh             - Deploy application to EKS
#   07-cleanup.sh                - Clean up all resources
#
# Environment Variables picked up form config.env file:
#   - AWS_REGION              - AWS region for deployment
#   - CLUSTER_NAME           - Name of the EKS cluster
#   - SERVICE_ACCOUNT_NAME   - Name of the Kubernetes service account
#   - ECR_REPO_NAME         - Name of the ECR repository
#   - DYNAMODB-TABLE-NAME - Name of the DynamoDB Table
#
# Usage: ./scripts/[script_name.sh]
#
#############################################################################

set -e

# Source configuration
if [ -f "./scripts/config.env" ]; then
    source ./scripts/config.env
else
    echo "Configuration file not found!"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print success message
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error message
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to print warning message
print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

# Function to print info message
print_info() {
    echo -e "ℹ $1"
}

# Function to print section header
print_section() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"

    # Check eksctl
    if ! command -v eksctl &> /dev/null; then
        print_error "eksctl is not installed"
        return 1
    fi
    print_success "eksctl is installed"

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        return 1
    fi
    print_success "AWS CLI is installed"

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured"
        return 1
    fi
    print_success "AWS credentials are configured"

    # Check cluster config file
    if [ ! -f "./cluster/inference-poc-clusterconfig.yaml" ]; then
        print_error "Cluster configuration file not found"
        return 1
    fi
    print_success "Cluster configuration file found"
}

# Function to create EKS cluster
create_cluster() {
    print_section "Creating EKS Cluster"
    
    print_info "Cluster name: ${CLUSTER_NAME}"
    print_info "AWS region: ${AWS_REGION}"
    
    if eksctl create cluster -f ./cluster/inference-poc-clusterconfig.yaml; then
        print_success "EKS cluster created successfully"
    else
        print_error "Failed to create EKS cluster"
        return 1
    fi
}

# Function to update kubeconfig
update_kubeconfig() {
    print_section "Updating Kubeconfig"
    
    if aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}; then
        print_success "Kubeconfig updated successfully"
    else
        print_error "Failed to update kubeconfig"
        return 1
    fi
}

# Function to verify cluster status
verify_cluster() {
    print_section "Verifying Cluster Status"
    
    local status=$(aws eks describe-cluster \
        --region ${AWS_REGION} \
        --name ${CLUSTER_NAME} \
        --query cluster.status \
        --output text)
    
    if [ "$status" == "ACTIVE" ]; then
        print_success "Cluster is active and ready"
    else
        print_warning "Cluster status: $status"
    fi
}

# Function to verify node group status
verify_nodegroup() {
    print_section "Verifying Node Group Status"
    
    # Wait for nodes to be ready
    print_info "Waiting for nodes to be ready..."
    local timeout=300  # 5 minutes timeout
    local start_time=$(date +%s)
    
    while true; do
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
        local desired_nodes=$NODE_GROUP_DESIRED_CAPACITY
        
        if [ "$ready_nodes" -ge "$desired_nodes" ]; then
            print_success "All nodes are ready ($ready_nodes/$desired_nodes)"
            break
        fi
        
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -gt $timeout ]; then
            print_error "Timeout waiting for nodes to be ready ($ready_nodes/$desired_nodes)"
            return 1
        fi
        
        sleep 10
    done
}

# Function to create DynamoDB table
create_dynamo_db_table() {
    print_section "Creating DynamoDB Table"
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name ${DYNAMODB_TABLE_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_info "DynamoDB table '${DYNAMODB_TABLE_NAME}' already exists"
        return 0
    fi
    
    print_info "Creating DynamoDB table '${DYNAMODB_TABLE_NAME}'..."
    
    if aws dynamodb create-table \
        --table-name ${DYNAMODB_TABLE_NAME} \
        --attribute-definitions \
            AttributeName=team_tag,AttributeType=S \
            AttributeName=version,AttributeType=S \
        --key-schema \
            AttributeName=team_tag,KeyType=HASH \
            AttributeName=version,KeyType=RANGE \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region ${AWS_REGION}; then
        print_success "DynamoDB table created successfully"
        
        # Wait for table to become active
        print_info "Waiting for table to become active..."
        aws dynamodb wait table-exists --table-name ${DYNAMODB_TABLE_NAME} --region ${AWS_REGION}
        print_success "Table is now active and ready to use"
    else
        print_error "Failed to create DynamoDB table"
        return 1
    fi
}


check_create_sns_topic() {
    print_section "Creating SNS topic"

    # Validate inputs
    if [[ -z "$TOPIC_NAME" ]]; then
        echo "Error: Missing required parameters."
        return 1
    fi

    echo "Checking if SNS topic '$TOPIC_NAME' exists .."
    topic_arn=$(aws sns list-topics --region "$AWS_REGION" --query "Topics[?ends_with(TopicARn,':$TOPIC_NAME')].TopicArn" --output text)

    if [[ -z "$topic_arn" ]]; then
        echo "Topic '$topic_name' doesn't exist. Creating now..."

        # Create the SNS topic
        topic_arn=$(aws sns create-topic --name "$TOPIC_NAME" --region "$AWS_REGION" --output text --query 'TopicArn')

        if [[ -z "$topic_arn" ]]; then
            echo "Error: Failed to create SNS topic."
            return 1
        fi

        echo "Successfully created SNS topic: \$topic_arn"
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name ${DYNAMODB_TABLE_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_info "DynamoDB table '${DYNAMODB_TABLE_NAME}' already exists"
        return 0
    fi
    
    print_info "Creating DynamoDB table '${DYNAMODB_TABLE_NAME}'..."
    
    if aws dynamodb create-table \
        --table-name ${DYNAMODB_TABLE_NAME} \
        --attribute-definitions \
            AttributeName=team_tag,AttributeType=S \
            AttributeName=version,AttributeType=S \
        --key-schema \
            AttributeName=team_tag,KeyType=HASH \
            AttributeName=version,KeyType=RANGE \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region ${AWS_REGION}; then
        print_success "DynamoDB table created successfully"
        
        # Wait for table to become active
        print_info "Waiting for table to become active..."
        aws dynamodb wait table-exists --table-name ${DYNAMODB_TABLE_NAME} --region ${AWS_REGION}
        print_success "Table is now active and ready to use"
    else
        print_error "Failed to create DynamoDB table"
        return 1
    fi

# Main function
main() {
    print_section "Starting Cluster Creation Process"
    
    # Check prerequisites
    check_prerequisites || exit 1
    
    # Create cluster
    create_cluster || exit 1
    
    # Update kubeconfig
    update_kubeconfig || exit 1
    
    # Verify cluster
    verify_cluster || exit 1
    
    # Verify node group
    verify_nodegroup || exit 1

    print_section "Cluster Creation Complete"
    print_success "EKS cluster has been successfully created and configured"
    print_info "Cluster name: ${CLUSTER_NAME}"
    print_info "Region: ${AWS_REGION}"
    print_info "Kubernetes version: ${KUBERNETES_VERSION}"
    
    # Create DynamoDB table
    create_dynamo_db_table || exit 1

    print_section "DynamoDB Table Creation Complete"

    # Create SNS topic
    check_create_sns_topic || exit 1

    print_section "SNS topic Creation Complete"
    
}

# Execute main function
main

