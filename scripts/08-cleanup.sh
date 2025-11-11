#!/bin/bash
#############################################################################
# Script Name: 09-cleanup.sh
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

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
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
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        print_error "AWS credentials are not configured"
        return 1
    fi
    
    print_success "All prerequisites satisfied"
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
    if kubectl delete -f ./eks-deployment/k8s/crds.yaml --ignore-not-found; then
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

# Function to delete VPC peering connection
delete_vpc_peering() {
    print_section "Deleting VPC Peering Connection"
    
    # Check if VPC peering ID is provided
    if [ -z "${VPC_PEERING_ID}" ]; then
        # Try to find VPC peering connection
        if [ -n "${HOST_VPC_ID}" ] && [ -n "${EKS_VPC_ID}" ]; then
            print_info "Looking for VPC peering connection between ${HOST_VPC_ID} and ${EKS_VPC_ID}..."
            
            VPC_PEERING_ID=$(aws ec2 describe-vpc-peering-connections \
                --filters "Name=requester-vpc-info.vpc-id,Values=${HOST_VPC_ID}" "Name=accepter-vpc-info.vpc-id,Values=${EKS_VPC_ID}" \
                --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' \
                --output text \
                --region ${AWS_REGION})
            
            if [ -z "${VPC_PEERING_ID}" ] || [ "${VPC_PEERING_ID}" == "None" ]; then
                print_info "No VPC peering connection found, skipping"
                return 0
            else
                print_info "Found VPC peering connection: ${VPC_PEERING_ID}"
            fi
        fi
        
        if [ -z "${VPC_PEERING_ID}" ] || [ "${VPC_PEERING_ID}" == "None" ]; then
            print_info "No VPC peering connection found, skipping"
            return 0
        else
            print_info "Found VPC peering connection: ${VPC_PEERING_ID}"
        fi
    fi

    # Delete the VPC peering connection
    print_info "Deleting VPC peering connection: ${VPC_PEERING_ID}"
    if aws ec2 delete-vpc-peering-connection \
        --vpc-peering-connection-id ${VPC_PEERING_ID} \
        --region ${AWS_REGION}; then
        print_success "VPC peering connection deleted"
    else
        print_warning "Failed to delete VPC peering connection"
    fi
}

# Function to clean up VPC peering configuration in config.env
clean_vpc_config() {
    print_section "Cleaning VPC Configuration in config.env"
    
    # Check if config.env exists
    if [ ! -f "./scripts/config.env" ]; then
        print_warning "config.env file not found, skipping cleanup"
        return 0
    fi
    
    print_info "Removing VPC-related entries from config.env"
    
    # Create a temporary file
    TMP_FILE=$(mktemp)
    
    # Filter out VPC-related entries
    grep -v "^HOST_VPC_ID=" ./scripts/config.env | \
    grep -v "^HOST_VPC_CIDR=" | \
    grep -v "^EKS_VPC_ID=" | \
    grep -v "^EKS_VPC_CIDR=" | \
    grep -v "^VPC_PEERING_ID=" > $TMP_FILE
    
    # Replace the original file
    mv $TMP_FILE ./scripts/config.env
    
    # Add empty placeholders for VPC-related entries
    echo "HOST_VPC_ID=\"\"" >> ./scripts/config.env
    echo "HOST_VPC_CIDR=\"\"" >> ./scripts/config.env
    echo "EKS_VPC_ID=\"\"" >> ./scripts/config.env
    echo "EKS_VPC_CIDR=\"\"" >> ./scripts/config.env
    echo "VPC_PEERING_ID=\"\"" >> ./scripts/config.env
    
    print_success "VPC configuration cleaned up in config.env"
}

# Function to delete ECR repository
delete_ecr_repository() {
    print_section "Deleting ECR Repository"
    
    print_info "Checking if ECR repository exists: ${ECR_REPO_NAME}"
    if ! aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_info "ECR repository ${ECR_REPO_NAME} does not exist, skipping"
        return 0
    fi
    
    print_info "Deleting ECR repository: ${ECR_REPO_NAME}"
    if aws ecr delete-repository \
        --repository-name ${ECR_REPO_NAME} \
        --force \
        --region ${AWS_REGION}; then
        print_success "ECR repository deleted"
    else
        print_warning "Failed to delete ECR repository"
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    print_section "Deleting IAM Roles"
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Check for the service account role
    ROLE_NAME="${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}"
    print_info "Checking for IAM role: $ROLE_NAME"
    
    if aws iam get-role --role-name $ROLE_NAME &>/dev/null; then
        print_info "Found role $ROLE_NAME, detaching policies..."
        
        # List attached policies
        attached_policies=$(aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[*].PolicyArn' --output text)
        
        # Detach all policies
        for policy_arn in $attached_policies; do
            policy_name=$(echo $policy_arn | awk -F '/' '{print $2}')
            print_info "Detaching policy: $policy_name"
            aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $policy_arn
        done
        
        # Delete the role
        print_info "Deleting role: $ROLE_NAME"
        if aws iam delete-role --role-name $ROLE_NAME; then
            print_success "Role deleted: $ROLE_NAME"
        else
            print_warning "Failed to delete role: $ROLE_NAME"
            print_info "Checking for instance profiles..."
            # Check if role has instance profiles
            profiles=$(aws iam list-instance-profiles-for-role --role-name $ROLE_NAME --query 'InstanceProfiles[*].InstanceProfileName' --output text)
            if [ -n "$profiles" ]; then
                print_info "Found instance profiles, removing role from profiles..."
                for profile in $profiles; do
                    aws iam remove-role-from-instance-profile --instance-profile-name $profile --role-name $ROLE_NAME
                done
                # Try deleting again
                print_info "Trying to delete role again..."
                aws iam delete-role --role-name $ROLE_NAME && print_success "Role deleted: $ROLE_NAME"
            fi
        fi
    else
        print_info "Role $ROLE_NAME does not exist, skipping"
    fi
}

# Function to delete IAM policies
delete_iam_policies() {
    print_section "Deleting IAM Policies"
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # List of policies to delete
    local policies=(
        "${IAM_POLICY_LB_NAME}"
        "${IAM_POLICY_BEDROCK_NAME}"
        "${IAM_POLICY_CONSOLE_NAME}"
        "${IAM_POLICY_DYNAMODB_NAME}"
    )
    
    for policy in "${policies[@]}"; do
        print_info "Checking policy: $policy"
        
        # Get policy ARN
        policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy}"
        
        # Check if policy exists
        if ! aws iam get-policy --policy-arn $policy_arn &>/dev/null; then
            print_info "Policy $policy does not exist, skipping"
            continue
        fi
        
        # Detach policy from all entities
        print_info "Detaching policy from all entities..."
        
        # Get all attached roles
        attached_roles=$(aws iam list-entities-for-policy --policy-arn $policy_arn --entity-filter Role --query 'PolicyRoles[*].RoleName' --output text)
        
        # Detach from roles
        for role in $attached_roles; do
            print_info "Detaching policy from role: $role"
            aws iam detach-role-policy --role-name $role --policy-arn $policy_arn
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

# Function to delete EKS cluster
delete_cluster() {
    print_section "Deleting EKS Cluster"
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_info "Cluster ${CLUSTER_NAME} does not exist, skipping"
        return 0
    fi
    
    print_info "Deleting cluster: ${CLUSTER_NAME}"
    if eksctl delete cluster \
        --name ${CLUSTER_NAME} \
        --region ${AWS_REGION} \
        --wait; then
        print_success "Cluster deleted"
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
        --region ${AWS_REGION}; then
        print_success "DynamoDB table deleted"
    else
        print_warning "Failed to delete DynamoDB table"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    print_section "Deleting SNS Topic"

    # Get topic ARN
    topic_arn=$(aws sns list-topics --region ${AWS_REGION} --query "Topics[?ends_with(TopicArn, ':${TOPIC_NAME}')].TopicArn" --output text)
    
    if [ -z "$topic_arn" ] || [ "$topic_arn" == "None" ]; then
        print_info "SNS topic ${TOPIC_NAME} does not exist, skipping"
        return 0
    fi
    
    print_info "Deleting SNS topic: ${topic_arn}"
    if aws sns delete-topic \
        --topic-arn ${topic_arn} \
        --region ${AWS_REGION}; then
        print_success "SNS topic deleted"
    else
        print_warning "Failed to delete SNS topic"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_section "Verifying Cleanup"
    
    local all_clean=true
    
    # Check if cluster still exists
    if aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_warning "EKS cluster ${CLUSTER_NAME} still exists"
        all_clean=false
    fi
    
    # Check if ECR repository still exists
    if aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_warning "ECR repository ${ECR_REPO_NAME} still exists"
        all_clean=false
    fi
    
    # Check if DynamoDB table still exists
    if aws dynamodb describe-table --table-name ${DYNAMODB_TABLE_NAME} --region ${AWS_REGION} &>/dev/null; then
        print_warning "DynamoDB table ${DYNAMODB_TABLE_NAME} still exists"
        all_clean=false
    fi

    # Check if VPC peering connection still exists
    if [ -n "${VPC_PEERING_ID}" ] && aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids ${VPC_PEERING_ID} --region ${AWS_REGION} &>/dev/null; then
        print_warning "VPC peering connection ${VPC_PEERING_ID} still exists"
        all_clean=false
    fi

    # Check if IAM policies still exist
    for policy in "${IAM_POLICY_LB_NAME}" "${IAM_POLICY_BEDROCK_NAME}" "${IAM_POLICY_CONSOLE_NAME}" "${IAM_POLICY_DYNAMODB_NAME}"; do
        policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy}"
        if aws iam get-policy --policy-arn $policy_arn &>/dev/null; then
            print_warning "IAM policy ${policy} still exists"
            all_clean=false
        fi
    done
    
    # Check if IAM roles still exist
    ROLE_NAME="${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}"
    if aws iam get-role --role-name $ROLE_NAME &>/dev/null; then
        print_warning "IAM role ${ROLE_NAME} still exists"
        all_clean=false
    fi
    
    if [ "$all_clean" = true ]; then
        print_success "All resources have been successfully cleaned up"
    else
        print_warning "Some resources may still exist. Please check the AWS Console"
    fi
}

# Main function
main() {
    print_section "Starting Cleanup Process"
    
    # Check prerequisites
    check_prerequisites || exit 1
    
    # Delete Kubernetes resources
    delete_kubernetes_resources || true
    
    # Delete service accounts
    delete_service_accounts || true
    
    # Delete VPC peering connection
    delete_vpc_peering || true
    
    # Clean up VPC configuration in config.env
    clean_vpc_config || true
    
    # Delete ECR repository
    delete_ecr_repository || true
    
    # Delete cluster first (clean up many attached resources)
    delete_cluster || true

    # Wait for cluster deletion to complete
    print_info "Waiting for cluster deletion to complete..."
    sleep 30
    
    # Delete IAM roles (after cluster deletion)
    delete_iam_roles || true

    # Delete IAM policies
    delete_iam_policies
    
    # Delete DynamoDB table
    delete_dynamodb_table || true
    
    # Delete SNS topic
    delete_sns_topic || true
    
    # Verify cleanup
    verify_cleanup

    print_section "Cleanup Complete"
    print_info "If you experienced any errors, please check the AWS Console to ensure all resources were properly deleted"
}

# Execute main function
main
