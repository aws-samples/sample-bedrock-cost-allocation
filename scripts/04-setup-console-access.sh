#!/bin/bash
#############################################################################
# Script Name: 04-setup-console-access.sh
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

# Function to setup AWS region from config
setup_aws_region() {
    print_section "Setting up AWS Region"

    if [ -f "./scripts/config.env" ]; then
        if grep -q "^AWS_REGION=" "./scripts/config.env"; then
            AWS_REGION=$(grep "^AWS_REGION=" "./scripts/config.env" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d '[:space:]')
            print_info "Found AWS_REGION in config.env: $AWS_REGION"
        else
            print_error "AWS_REGION not found in config.env"
            exit 1
        fi
    else
        print_error "config.env file not found"
        exit 1
    fi

    # Verify if the region exists
    if ! aws ec2 describe-regions --region-names $AWS_REGION >/dev/null 2>&1; then
        print_error "Invalid AWS region: $AWS_REGION"
        exit 1
    fi

    export AWS_REGION
    print_success "Using AWS Region: $AWS_REGION"
}

# Function to print section header
print_section() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"

    #setup region
    setup_aws_region

    # Export AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_error "Failed to get AWS Account ID"
        return 1
    fi
    print_success "AWS Account ID: ${AWS_ACCOUNT_ID}"

    # Construct Console Role ARN
    CONSOLE_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CONSOLE_ROLE_NAME}"
    print_info "Console Role ARN: ${CONSOLE_ROLE_ARN}"

    # Check required files
    if [ ! -f "./iam/eks-console-policy.json" ]; then
        print_error "Console policy file not found"
        return 1
    fi
    print_success "Console policy file found"

    # Check if console role exists
    if ! aws iam get-role --role-name ${CONSOLE_ROLE_NAME} &>/dev/null; then
        print_error "Role ${CONSOLE_ROLE_NAME} does not exist"
        print_info "Please create the role first with appropriate trust relationships"
        return 1
    fi
    print_success "Console role exists"
}

# Function to create console policy
create_console_policy() {
    print_section "Creating Console Access Policy"
    
    print_info "Creating policy: ${IAM_POLICY_CONSOLE_NAME}"
    
    if aws iam create-policy \
        --policy-name ${IAM_POLICY_CONSOLE_NAME} \
        --policy-document file://./iam/eks-console-policy.json \
        --description "EKS Console Access Policy" 2>/dev/null; then
        print_success "Console policy created"
    else
        print_warning "Policy might already exist, continuing..."
    fi
}

# Function to create IAM identity mapping
create_identity_mapping() {
    print_section "Creating IAM Identity Mapping"
    
    print_info "Mapping role to EKS cluster..."
    
    if eksctl create iamidentitymapping \
        --cluster ${CLUSTER_NAME} \
        --region ${AWS_REGION} \
        --arn ${CONSOLE_ROLE_ARN} \
        --username admin \
        --group system:masters \
        --group eks-console-dashboard-full-access-group; then
        print_success "IAM identity mapping created"
    else
        print_error "Failed to create IAM identity mapping"
        return 1
    fi
}

# Function to apply RBAC configuration
apply_rbac() {
    print_section "Applying RBAC Configuration"
    
    print_info "Applying RBAC rules..."
    
    if kubectl apply -f ./eks-deployment/cluster/eks-console-access.yaml; then
        print_success "RBAC configuration applied"
    else
        print_error "Failed to apply RBAC configuration"
        return 1
    fi
}

# Function to verify configuration
verify_configuration() {
    print_section "Verifying Configuration"
    
    print_info "Checking cluster role binding..."
    
    if kubectl get clusterrolebinding eks-console-dashboard-full-access-binding; then
        print_success "Cluster role binding verified"
    else
        print_error "Cluster role binding verification failed"
        return 1
    fi
}

# Main function
main() {
    print_section "Starting Console Access Setup"
    
    # Check prerequisites
    check_prerequisites || exit 1
    
    # Create and configure console access
    create_console_policy || exit 1
    create_identity_mapping || exit 1
    apply_rbac || exit 1
    verify_configuration || exit 1
    
    print_section "Console Access Setup Complete"
    print_success "EKS console access has been configured successfully"
    print_info "Role ARN: ${CONSOLE_ROLE_ARN}"
    print_info "Cluster: ${CLUSTER_NAME}"
    print_info "Region: ${AWS_REGION}"
}

# Execute main function
main
