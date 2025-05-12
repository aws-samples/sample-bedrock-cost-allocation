#!/bin/bash
#############################################################################
# Script Name: 07-cleanup.sh
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

# Function to print messages
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}! $1${NC}"; }
print_info() { echo -e "ℹ $1"; }
print_section() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

# Function to setup AWS region from config
setup_aws_region() {
    print_section "Setting up AWS Region"

    if [ -f "./scripts/config.env" ]; then
        if grep -q "^AWS_REGION=" "./scripts/config.env"; then
            AWS_REGION=$(grep "^AWS_REGION=" "./scripts/config.env" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d '[:space:]')
            print_info "Found AWS_REGION in config.env: $AWS_REGION"
            
            # Verify if the region exists
            if ! aws ec2 describe-regions --region-names $AWS_REGION >/dev/null 2>&1; then
                print_error "Invalid AWS region: $AWS_REGION"
                exit 1
            fi
            
            export AWS_REGION
            export AWS_DEFAULT_REGION=$AWS_REGION
            print_success "Using AWS Region: $AWS_REGION"
        else
            print_error "AWS_REGION not found in config.env"
            exit 1
        fi
    else
        print_error "config.env file not found"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"

    # Export AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_error "Failed to get AWS Account ID"
        return 1
    fi
    print_success "AWS Account ID: $AWS_ACCOUNT_ID"

    #setup region
    setup_aws_region

    # Check required tools
    local tools=("kubectl" "eksctl" "aws")
    for tool in "${tools[@]}"; do
        if ! command -v $tool &>/dev/null; then
            print_error "$tool is required but not installed"
            return 1
        fi
    done
    print_success "All required tools are installed"
}

# Function to delete Kubernetes resources
delete_kubernetes_resources() {
    print_section "Deleting Kubernetes Resources"
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &>/dev/null; then
        print_info "Cluster not accessible, skipping Kubernetes resource deletion"
        return 0
    fi
    
    local resources=(
        "service/inferencepoc-service"
        "deployment/inferencepoc-deployment"
        "serviceaccount/${SERVICE_ACCOUNT_NAME}"
    )
    
    for resource in "${resources[@]}"; do
        print_info "Deleting $resource..."
        if kubectl delete $resource --ignore-not-found; then
            print_success "$resource deleted"
        else
            print_warning "Failed to delete $resource"
        fi
    done
    
    # Delete CRDs
    print_info "Deleting CRDs..."
    if kubectl delete -f ./k8s/crds.yaml --ignore-not-found; then
        print_success "CRDs deleted"
    else
        print_warning "Failed to delete CRDs"
    fi
}

# Function to delete service accounts
delete_service_accounts() {
    print_section "Deleting Service Accounts"
    
    print_info "Deleting IAM service account..."
    if eksctl delete iamserviceaccount \
        --cluster=${CLUSTER_NAME} \
        --name=${SERVICE_ACCOUNT_NAME} \
        --namespace=${SERVICE_ACCOUNT_NAMESPACE} \
        --region=${AWS_REGION} \
        --wait; then
        print_success "Service account deleted"
    else
        print_warning "Failed to delete service account"
    fi
}

# Function to delete IAM policies
delete_iam_policies() {
    print_section "Deleting IAM Policies"
    
    local policies=(
        "${IAM_POLICY_LB_NAME}"
        "${IAM_POLICY_BEDROCK_NAME}"
        "${IAM_POLICY_CONSOLE_NAME}"
        "${IAM_POLICY_DYNAMODB_NAME}"
    )
    
    for policy in "${policies[@]}"; do
        print_info "Deleting policy: $policy"
        local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy}"
        
        # Check if policy exists
        if ! aws iam get-policy --policy-arn $policy_arn &>/dev/null; then
            print_info "Policy $policy does not exist, skipping"
            continue
        fi

        # List and detach from all roles
        print_info "Detaching policy from roles..."
        local roles=$(aws iam list-entities-for-policy --policy-arn $policy_arn --entity-filter Role --query 'PolicyRoles[*].RoleName' --output text)
        for role in $roles; do
            print_info "Detaching from role: $role"
            aws iam detach-role-policy \
                --role-name $role \
                --policy-arn $policy_arn
        done

        # Delete all non-default versions
        print_info "Deleting policy versions..."
        local versions=$(aws iam list-policy-versions --policy-arn $policy_arn --query 'Versions[?!IsDefaultVersion].VersionId' --output text)
        for version in $versions; do
            aws iam delete-policy-version \
                --policy-arn $policy_arn \
                --version-id $version
        done

        # Delete the policy
        if aws iam delete-policy --policy-arn $policy_arn; then
            print_success "Policy deleted: $policy"
        else
            print_warning "Failed to delete policy: $policy"
            print_info "Checking for remaining attachments..."
            aws iam list-entities-for-policy --policy-arn $policy_arn
        fi
    done
}


# Function to delete ECR repository
delete_ecr_repository() {
    print_section "Deleting ECR Repository"
    
    print_info "Deleting repository: ${ECR_REPO_NAME}"
    if ! aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_info "ECR repository ${ECR_REPO_NAME} does not exist, skipping"
        return 0
    fi
    
    if aws ecr delete-repository \
        --repository-name ${ECR_REPO_NAME} \
        --force \
        --region ${AWS_REGION} &>/dev/null; then
        print_success "ECR repository deleted"
    else
        print_warning "Failed to delete ECR repository"
    fi
}

# Function to delete cluster
delete_cluster() {
    print_section "Deleting EKS Cluster"
    
    print_info "Deleting cluster: ${CLUSTER_NAME}"
    if ! aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_info "Cluster ${CLUSTER_NAME} does not exist, skipping"
        return 0
    fi

    if eksctl delete cluster \
        --name ${CLUSTER_NAME} \
        --region ${AWS_REGION} \
        --wait; then
        print_success "Cluster deleted successfully"
    else
        print_error "Failed to delete cluster"
        return 1
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    print_section "Deleting DynamoDB Table"

    print_info "Deleting table: ${DYNAMODB_TABLE_NAME}"
    if ! aws dynamodb describe-table --table-name ${DYNAMODB_TABLE_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_info "Table ${DYNAMODB_TABLE_NAME} does not exist, skipping"
        return 0
    fi

    if aws dynamodb delete-table \
        --table-name ${DYNAMODB_TABLE_NAME} \
        --region ${AWS_REGION} &>/dev/null; then
        print_success "DynamoDB table deleted"
    else
        print_warning "Failed to delete DynamoDB table"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_section "Verifying Cleanup"
    local all_clean=true

    # Check if cluster still exists
    if aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_warning "Cluster ${CLUSTER_NAME} still exists"
        all_clean=false
    fi

    # Check if ECR repository still exists
    if aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_warning "ECR repository ${ECR_REPO_NAME} still exists"
        all_clean=false
    fi

    # Check if IAM policies still exist
    for policy in "${IAM_POLICY_LB_NAME}" "${IAM_POLICY_BEDROCK_NAME}" "${IAM_POLICY_CONSOLE_NAME}" "${IAM_POLICY_DYNAMODB_NAME}"; do
        local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy}"
        if aws iam get-policy --policy-arn $policy_arn &>/dev/null; then
            print_warning "IAM policy ${policy} still exists"
            all_clean=false
        fi
    done

    if [ "$all_clean" = true ]; then
        print_success "All resources have been cleaned up successfully"
    else
        print_warning "Some resources may still exist. Please check AWS Console"
    fi
}

# Main function
main() {
    print_section "Starting Cleanup Process"
    
    # Check prerequisites
    check_prerequisites || exit 1
    
    # Setup AWS Region
    setup_aws_region
    
    # Delete resources in order
    delete_kubernetes_resources
    
    # Wait for kubernetes resources to be fully deleted
    print_info "Waiting for Kubernetes resources to be fully deleted..."
    sleep 30
    
    delete_service_accounts
    
    # Wait for service accounts to be fully deleted
    print_info "Waiting for service accounts to be fully deleted..."
    sleep 30
    
    # Delete cluster first (clean up many attached resources)
    delete_cluster || true
    
    # Wait for cluster deletion to complete
    print_info "Waiting for cluster deletion to complete..."
    sleep 30
    
    # Delete IAM policies
    delete_iam_policies
    
    # Finally delete ECR repository
    delete_ecr_repository
    
    # Delete DynamoDB table
    delete_dynamodb_table

    # Verify cleanup
    verify_cleanup
    
    print_section "Cleanup Complete"
    print_info "If you experienced any errors, please check the AWS Console to ensure all resources were properly deleted"
}

# Execute main function
main
