#!/bin/bash
#############################################################################
# Script Name: 07-deploy-app.sh
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

    # Check AWS credentials and configuration
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured"
        return 1
    fi
    
    # Export AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS Account ID: $AWS_ACCOUNT_ID"

    # Check and export AWS Region
    setup_aws_region
    print_success "AWS Region: $AWS_REGION"

    # Check kubectl
    if ! command -v kubectl &>/dev/null; then
        print_error "kubectl not installed"
        return 1
    fi
    print_success "kubectl is installed"

    # Check cluster access
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Cannot access Kubernetes cluster"
        return 1
    fi
    print_success "Cluster access confirmed"

    # Verify ECR repository exists
    if ! aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} --region ${AWS_REGION} >/dev/null 2>&1; then
        print_error "ECR repository ${ECR_REPO_NAME} not found"
        return 1
    fi
    print_success "ECR repository verified"

    # Check required files
    local required_files=(
        "./eks-deployment/k8s/crds.yaml"
        "./eks-deployment/k8s/inferencepoc-service.yaml"
        "./eks-deployment/k8s/inferenceapp-amd64.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Required file not found: $file"
            return 1
        fi
    done
    print_success "All required files found"
}

# Function to update deployment image
update_deployment_image() {
    print_section "Updating Deployment Image Reference"

    local image_url="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest-amd64"
    
    # Create backup of original file
    cp eks-deployment/k8s/inferenceapp-amd64.yaml eks-deployment/k8s/inferenceapp-amd64.yaml.bak
    
    # Update image reference
    sed -i "s|image: .*|image: ${image_url}|" eks-deployment/k8s/inferenceapp-amd64.yaml
    
    print_success "Updated image reference to: ${image_url}"
}

# Function to verify image exists in ECR
verify_ecr_image() {
    print_section "Verifying ECR Image"

    local image_tag="latest-amd64"
    
    if aws ecr describe-images \
        --repository-name ${ECR_REPO_NAME} \
        --image-ids imageTag=${image_tag} \
        --region ${AWS_REGION} >/dev/null 2>&1; then
        print_success "Image ${ECR_REPO_NAME}:${image_tag} exists in ECR"
        return 0
    else
        print_error "Image ${ECR_REPO_NAME}:${image_tag} not found in ECR"
        return 1
    fi
}

# Function to deploy application
deploy_application() {
    print_section "Deploying Application"
    
    # Delete existing deployment if it exists
    kubectl delete deployment inferencepoc-deployment --ignore-not-found
    
    print_info "Applying deployment..."
    if kubectl apply -f eks-deployment/k8s/inferenceapp-amd64.yaml; then
        print_success "Deployment applied successfully"
    else
        print_error "Failed to apply deployment"
        return 1
    fi
}

# Function to wait for deployment
wait_for_deployment() {
    print_section "Waiting for Deployment"
    
    local timeout=300
    local start_time=$(date +%s)
    
    while true; do
        local status=$(kubectl get deployment inferencepoc-deployment -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
        local ready_replicas=$(kubectl get deployment inferencepoc-deployment -o jsonpath='{.status.readyReplicas}')
        
        if [ "$status" == "True" ] && [ "$ready_replicas" == "2" ]; then
            print_success "Deployment is ready"
            return 0
        fi
        
        if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
            print_error "Deployment timeout after ${timeout}s"
            kubectl describe deployment inferencepoc-deployment
            return 1
        fi
        
        print_info "Waiting for deployment to be ready..."
        sleep 10
    done
}

# Function to deploy and verify service
deploy_service() {
    print_section "Deploying Service"
    
    print_info "Applying service..."
    if ! kubectl apply -f eks-deployment/k8s/inferencepoc-service.yaml; then
        print_error "Failed to deploy service"
        return 1
    fi
    print_success "Service deployed successfully"

    print_info "Waiting for LoadBalancer..."
    local timeout=300
    local start_time=$(date +%s)
    
    while true; do
        local service_url=$(kubectl get svc inferencepoc-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        
        if [ -n "$service_url" ]; then
            print_success "LoadBalancer endpoint: ${service_url}"
            export SERVICE_URL=$service_url
            return 0
        fi
        
        if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
            print_error "Service timeout after ${timeout}s"
            kubectl describe service inferencepoc-service
            return 1
        fi
        
        print_info "Waiting for LoadBalancer to be ready..."
        sleep 60
    done
}

# Function to test endpoints
test_endpoints() {
    print_section "Testing Endpoints"
    
    local endpoints=(
        "hello"
        "bedrock-health"
    )

    for endpoint in "${endpoints[@]}"; do
        print_info "Testing /${endpoint}..."
        if curl -s -f "http://${SERVICE_URL}/${endpoint}" >/dev/null 2>&1; then
            print_success "Endpoint /${endpoint} is accessible"
        else
            print_warning "Endpoint /${endpoint} is not responding"
        fi
    done
}

# Main function
main() {
    print_section "Starting Application Deployment"
    
    # Initial checks
    check_prerequisites || exit 1
    verify_ecr_image || exit 1
    update_deployment_image || exit 1
    
    # Deploy application
    deploy_application || exit 1
    wait_for_deployment || exit 1
    
    # Deploy and test service
    deploy_service || exit 1
    
    sleep 30
    print_section "Deployment Complete"
    sleep 15
    print_success "Application has been deployed successfully"
    print_section "Waiting for Endpoints to be ready"
    sleep 60
    if [ -n "$SERVICE_URL" ]; then
        print_info "Application endpoints:"
        print_info "- Health check: http://${SERVICE_URL}/hello"
        print_info "- Bedrock health: http://${SERVICE_URL}/bedrock-health"
        
        # Optional: Test endpoints
	sleep 120
        read -p "Would you like to test the endpoints? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            test_endpoints
        fi
    else
        print_warning "Service URL not available. Please check service status."
    fi
}

# Execute main function
main
