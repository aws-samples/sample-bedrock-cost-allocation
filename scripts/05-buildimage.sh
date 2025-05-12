#!/bin/bash
#############################################################################
# Script Name: 05-buildimage.sh
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

    # Export AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_error "Failed to get AWS Account ID"
        return 1
    fi
    print_success "AWS Account ID: ${AWS_ACCOUNT_ID}"

    #setup region
    setup_aws_region

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        return 1
    fi
    print_success "Docker is installed"

    # Check application files
    if [ ! -d "./app" ]; then
        print_error "Application directory not found"
        return 1
    fi
    print_success "Application directory found"
}

# Function to check and fix Docker permissions
check_docker_permissions() {
    print_section "Checking Docker Permissions"

    # Check if user is in docker group
    if ! groups | grep -q docker; then
        print_info "Adding user to docker group..."
        sudo usermod -aG docker $USER
        
        # Get absolute paths
        CURRENT_DIR=$(pwd)
        SCRIPT_PATH="$CURRENT_DIR/$(realpath --relative-to="$CURRENT_DIR" "$0")"
        
        # Create a temporary script to handle the re-execution
        TMP_SCRIPT=$(mktemp)
        cat << 'EOF' > $TMP_SCRIPT
#!/bin/bash
# Get the original script path and directory from arguments
ORIGINAL_SCRIPT=$1
WORK_DIR=$2

# Wait briefly for group changes to propagate
sleep 2

# Execute the original script with the new docker group
cd "$WORK_DIR" && sg docker -c "$ORIGINAL_SCRIPT"

# Clean up
rm -f "$0"
EOF
        
        chmod +x $TMP_SCRIPT
        print_info "Restarting script with new group permissions..."
        exec $TMP_SCRIPT "$SCRIPT_PATH" "$CURRENT_DIR"
        exit 0
    fi

    # Test Docker access
    if ! docker ps >/dev/null 2>&1; then
        print_warning "Cannot access Docker daemon. Attempting to fix..."
        sudo systemctl restart docker
        sleep 2
        
        # Test again
        if ! docker ps >/dev/null 2>&1; then
            print_error "Still cannot access Docker daemon. Please ensure Docker is properly installed and running"
            exit 1
        fi
    fi

    print_success "Docker permissions verified"
}


# Function to setup buildx
setup_buildx() {
    print_section "Setting up Docker Buildx"
    
    print_info "Creating and configuring buildx builder..."
    
    docker buildx create --use --name multiarch-builder || true
    if docker buildx inspect --bootstrap; then
        print_success "Buildx setup complete"
    else
        print_error "Failed to setup buildx"
        return 1
    fi
}

# Function to create ECR repository
create_ecr_repo() {
    print_section "Creating ECR Repository"
    
    print_info "Checking ECR repository: ${ECR_REPO_NAME}"
    
    if ! aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region ${AWS_REGION} >/dev/null 2>&1; then
        print_info "Creating new ECR repository..."
        if aws ecr create-repository \
            --repository-name ${ECR_REPO_NAME} \
            --region ${AWS_REGION} \
            --image-scanning-configuration scanOnPush=true; then
            print_success "ECR repository created"
        else
            print_error "Failed to create ECR repository"
            return 1
        fi
    else
        print_success "ECR repository already exists"
    fi
}

# Function to build and push image
build_and_push() {
    local arch=$1
    local platform="linux/$arch"
    local repo_url="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
    
    print_section "Building for $platform"
    
    print_info "Building Docker image..."
    if docker buildx build --platform $platform \
        -t ${repo_url}:latest-${arch} \
        --push \
        ./app/; then
        print_success "Image built and pushed for $arch"
    else
        print_error "Failed to build image for $arch"
        return 1
    fi
}

# Function to verify image
verify_image() {
    local arch=$1
    local repo_url="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
    
    print_info "Verifying image for $arch..."
    if aws ecr describe-images \
        --repository-name ${ECR_REPO_NAME} \
        --image-ids imageTag=latest-${arch} \
        --region ${AWS_REGION} >/dev/null 2>&1; then
        print_success "Image verified for $arch"
        return 0
    else
        print_error "Image verification failed for $arch"
        return 1
    fi
}

# Main function
main() {
    print_section "Starting Image Build Process"
    
    # Check Docker permissions first
    check_docker_permissions

    # Check prerequisites
    check_prerequisites || exit 1
    
    # Login to ECR
    print_info "Logging into ECR..."
    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    print_success "ECR login successful"
    
    # Setup buildx
    setup_buildx || exit 1
    
    # Create ECR repository
    create_ecr_repo || exit 1
    
    # Build images based on BUILD_ARCHITECTURE setting
    case $BUILD_ARCHITECTURE in
        "arm64")
            build_and_push "arm64" || exit 1
            verify_image "arm64" || exit 1
            ;;
        "amd64")
            build_and_push "amd64" || exit 1
            verify_image "amd64" || exit 1
            ;;
        "both")
            build_and_push "arm64" || exit 1
            verify_image "arm64" || exit 1
            build_and_push "amd64" || exit 1
            verify_image "amd64" || exit 1
            ;;
        *)
            print_error "Invalid BUILD_ARCHITECTURE value. Supported values: arm64, amd64, both"
            exit 1
            ;;
    esac
    
    print_section "Build Process Complete"
    print_success "All images have been built and pushed successfully"
    print_info "Repository: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
    print_info "ARM64 image tag: latest-arm64"
    print_info "AMD64 image tag: latest-amd64"
}

# Execute main function
main
