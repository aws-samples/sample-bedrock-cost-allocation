#!/bin/bash
#############################################################################
# Script Name: 00-install-eks-prerequisites.sh
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

# Define required tools and their packages
declare -A REQUIRED_TOOLS=(
    ["curl"]="curl"
    ["wget"]="wget"
    ["git"]="git"
    ["unzip"]="unzip"
    ["tar"]="tar"
    ["jq"]="jq"
    ["yq"]="yq"
    ["openssl"]="openssl"
    ["grep"]="grep"
    ["sed"]="sed"
    ["awk"]="gawk"
    ["python3"]="python3"
    ["pip3"]="python3-pip"
)

# Function to detect Amazon Linux version
detect_amazon_linux_version() {
    print_section "Detecting Amazon Linux Version"

    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "$ID" == "amzn" ]]; then
            if [[ "$VERSION_ID" == "2" ]]; then
                print_success "Detected Amazon Linux 2"
                AMAZON_LINUX_VERSION="2"
            elif [[ "$VERSION_ID" == "2023" ]]; then
                print_success "Detected Amazon Linux 2023"
                AMAZON_LINUX_VERSION="2023"
            else
                print_error "Unsupported Amazon Linux version"
                exit 1
            fi
        else
            print_error "This script only supports Amazon Linux"
            exit 1
        fi
    else
        print_error "Could not determine OS version"
        exit 1
    fi
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

# Function to check system requirements
check_system_requirements() {
    print_section "Checking System Requirements"
    
    # Check CPU architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
        print_error "Unsupported architecture: $ARCH. x86_64 or arm64 required."
        return 1
    fi
    print_success "Architecture: $ARCH"

    # Check memory
    MEMORY=$(free -g | awk '/^Mem:/{print $2}')
    if [ $MEMORY -lt 4 ]; then
        print_error "Minimum 4GB RAM required. Current: ${MEMORY}GB"
        return 1
    fi
    print_success "Memory: ${MEMORY}GB"

    # Check disk space
    DISK_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ $DISK_SPACE -lt 5 ]; then
        print_warning "Recommended minimum 5GB free disk space. Current: ${DISK_SPACE}GB"
    fi
    print_success "Disk space: ${DISK_SPACE}GB"

    # Check kernel version
    KERNEL_VERSION=$(uname -r)
    print_info "Kernel version: $KERNEL_VERSION"
}

# Function to install package based on Amazon Linux version
install_package() {
    local package_name=$1
    
    if [ "$AMAZON_LINUX_VERSION" == "2" ]; then
        sudo yum install -y $package_name
    elif [ "$AMAZON_LINUX_VERSION" == "2023" ]; then
        sudo dnf install -y $package_name
    fi
}

# Function to check AWS service endpoints
check_aws_endpoints() {
    print_section "Checking AWS Service Endpoints"
    
    local services=(
        "ecr"
        "eks"
        "sts"
        "bedrock"
    )

    for service in "${services[@]}"; do
        print_info "Testing AWS $service service..."
        if aws $service help >/dev/null 2>&1; then
            print_success "AWS $service service is accessible"
        else
            print_warning "AWS $service service might not be accessible"
        fi
    done

    # Test AWS CLI connectivity
    print_info "Testing AWS CLI connectivity..."
    if aws sts get-caller-identity >/dev/null 2>&1; then
        print_success "AWS CLI connectivity verified"
    else
        print_error "Cannot connect to AWS services using AWS CLI"
        return 1
    fi
}

# Function to check and install basic tools
check_and_install_basic_tools() {
    print_section "Checking and Installing Basic Tools"

    for tool in "${!REQUIRED_TOOLS[@]}"; do
        if ! command -v $tool &>/dev/null; then
            print_info "Installing $tool..."
            if [ "$tool" = "yq" ]; then
                install_yq
            else
                install_package "${REQUIRED_TOOLS[$tool]}"
            fi
        fi
        
        if command -v $tool &>/dev/null; then
            print_success "$tool is installed"
            case $tool in
                curl|wget|git|openssl|python3|pip3)
                    $tool --version 2>/dev/null || true
                    ;;
            esac
        else
            print_error "Failed to install $tool"
            return 1
        fi
    done
}

# Function to install yq
install_yq() {
    print_section "Installing yq"
    
    if command -v yq &>/dev/null; then
        print_success "yq is already installed"
        return 0
    fi

    ARCH=$(uname -m)
    YQ_VERSION="v4.40.5"
    
    case $ARCH in
        x86_64)
            BINARY_ARCH="amd64"
            ;;
        aarch64)
            BINARY_ARCH="arm64"
            ;;
        *)
            print_error "Unsupported architecture for yq: $ARCH"
            return 1
            ;;
    esac

    sudo wget -q https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${BINARY_ARCH} -O /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq
    print_success "yq installed"
}

# Function to install Docker
install_docker() {
    print_section "Installing Docker"
    
    if command -v docker &>/dev/null; then
        print_success "Docker is already installed"
        docker --version
        return 0
    fi

    if [ "$AMAZON_LINUX_VERSION" == "2" ]; then
        sudo yum install -y docker
    elif [ "$AMAZON_LINUX_VERSION" == "2023" ]; then
        sudo dnf install -y docker
    fi

    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    
    if command -v docker &>/dev/null; then
        print_success "Docker installed and configured"
        docker --version
    else
        print_error "Docker installation failed"
        return 1
    fi
}

# Function to install kubectl
install_kubectl() {
    print_section "Installing kubectl"
    
    if command -v kubectl &>/dev/null; then
        if kubectl version --client 2>/dev/null | grep -q 'Client Version'; then
            print_success "kubectl is already installed properly"
            kubectl version --client
            return 0
        else
            print_warning "Existing kubectl installation appears corrupt, reinstalling..."
            sudo rm -f /usr/local/bin/kubectl
        fi
    fi

    print_info "Installing kubectl..."
    
    # For Amazon Linux 2023
    if [ "$AMAZON_LINUX_VERSION" == "2023" ]; then
        # Create kubernetes.repo
        cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF
        # Install kubectl
        sudo dnf install -y kubectl
    else
        # For Amazon Linux 2
        cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
        sudo yum install -y kubectl
    fi

    # Verify installation
    if kubectl version --client; then
        print_success "kubectl installed successfully"
        # Set up kubectl bash completion
        kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
        print_success "kubectl bash completion installed"
    else
        print_error "kubectl installation failed"
        return 1
    fi

    # Create kubectl config directory if it doesn't exist
    mkdir -p ~/.kube
}


# Function to install eksctl
install_eksctl() {
    print_section "Installing eksctl"
    
    if command -v eksctl &>/dev/null; then
        print_success "eksctl is already installed"
        eksctl version
        return 0
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            BINARY_ARCH="amd64"
            ;;
        aarch64)
            BINARY_ARCH="arm64"
            ;;
        *)
            print_error "Unsupported architecture for eksctl: $ARCH"
            return 1
            ;;
    esac

    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_${BINARY_ARCH}.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    print_success "eksctl installed"
    eksctl version
}

# Function to check EC2 role and permissions
check_ec2_role() {
    print_section "Checking EC2 Instance and IAM Role"

    if ! curl -s http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        print_error "Not running on EC2 instance"
        return 1
    fi

    print_success "Running on EC2 instance"

    # Get instance ID
    local instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    print_info "Instance ID: $instance_id"

    # Check for assumed role first
    local identity_info=$(aws sts get-caller-identity --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
        local arn=$(echo $identity_info | jq -r .Arn)
        local account_id=$(echo $identity_info | jq -r .Account)

        if [[ $arn == *"assumed-role"* ]]; then
            local role_name=$(echo $arn | cut -d'/' -f2)
            print_success "Using assumed role: $role_name"

            # Check role permissions
            print_info "Checking role permissions..."
            
            # Define required permissions with their test commands
            declare -A required_permissions=(
                ["EKS"]="aws eks list-clusters --region $AWS_REGION"
                ["ECR"]="aws ecr describe-repositories --region $AWS_REGION"
                ["EC2"]="aws ec2 describe-instances --region $AWS_REGION"
                ["IAM"]="aws iam list-roles"
                ["Bedrock"]="aws bedrock list-foundation-models --region $AWS_REGION"
            )

            local all_permissions_ok=true
            for service in "${!required_permissions[@]}"; do
                if eval "${required_permissions[$service]}" &>/dev/null; then
                    print_success "✓ Has $service permissions"
                else
                    print_warning "! Missing $service permissions"
                    all_permissions_ok=false
                fi
            done

            if [ "$all_permissions_ok" = true ]; then
                print_success "Role has all required permissions"
            else
                print_warning "Some permissions are missing. Please ensure the role has the following permissions:"
                print_info "- eks:ListClusters"
                print_info "- ecr:DescribeRepositories"
                print_info "- ec2:DescribeInstances"
                print_info "- iam:ListRoles"
                print_info "- bedrock:ListFoundationModels"
            fi

            # Check role session duration
            local expiration=$(aws sts get-caller-identity --query 'Credentials.Expiration' --output text 2>/dev/null)
            if [ -n "$expiration" ]; then
                print_info "Role session expires: $expiration"
            fi

        else
            # Check for instance profile if no assumed role
            local instance_profile=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
            if [ -n "$instance_profile" ]; then
                print_success "Using instance profile: $instance_profile"
            else
                print_warning "No instance profile or assumed role found"
                print_info "Please ensure proper IAM permissions are configured"
            fi
        fi
    else
        print_error "Unable to get IAM role information"
        return 1
    fi

    # Verify AWS CLI default region
    local configured_region=$(aws configure get region)
    if [ "$configured_region" = "$AWS_REGION" ]; then
        print_success "AWS CLI region properly configured: $AWS_REGION"
    else
        print_warning "AWS CLI region mismatch (expected: $AWS_REGION, got: $configured_region)"
    fi
}



# Function to check EC2 instance role
check_ec2_role() {
    print_section "Checking EC2 Instance Role"

    # Check if running on EC2
    if curl -s http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        print_success "Running on EC2 instance"
        
        # Get instance profile name
        local instance_profile=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
        if [ -n "$instance_profile" ]; then
            print_success "Instance profile: $instance_profile"
            
            # Check if the role has necessary permissions
            print_info "Checking role permissions..."
            local required_services=("eks" "ecr" "bedrock")
            for service in "${required_services[@]}"; do
                if aws $service help &>/dev/null; then
                    print_success "Has access to $service service"
                else
                    print_warning "Missing access to $service service"
                fi
            done
        else
            print_warning "No instance profile attached"
        fi
    else
        print_warning "Not running on EC2 instance"
    fi
}


# Function to verify AWS configuration
verify_aws_configuration() {
    print_section "Verifying AWS Configuration"

    # Check AWS CLI version
    aws --version

    # Get and display account info
    if ! aws sts get-caller-identity &>/dev/null; then
        print_error "Unable to get AWS identity information"
        return 1
    fi

    local account_info=$(aws sts get-caller-identity --output json)
    local account_id=$(echo $account_info | jq -r .Account)
    local arn=$(echo $account_info | jq -r .Arn)
    
    print_success "AWS Account ID: $account_id"
    print_success "AWS User ARN: $arn"
    print_success "AWS Region: $AWS_REGION"

    # Test essential AWS services
    print_info "Testing AWS service access..."
    
    # Test EKS access
    if aws eks list-clusters --region $AWS_REGION &>/dev/null; then
        print_success "Access to EKS: Verified"
    else
        print_warning "Access to EKS: Not verified"
    fi

    # Test EC2 access
    if aws ec2 describe-vpcs --region $AWS_REGION &>/dev/null; then
        print_success "Access to EC2: Verified"
    else
        print_warning "Access to EC2: Not verified"
    fi

    # Test IAM access
    if aws iam list-roles &>/dev/null; then
        print_success "Access to IAM: Verified"
    else
        print_warning "Access to IAM: Not verified"
    fi

    # Test ECR access
    if aws ecr describe-repositories --region $AWS_REGION &>/dev/null; then
        print_success "Access to ECR: Verified"
    else
        print_warning "Access to ECR: Not verified"
    fi

    # Test Bedrock access
    if aws bedrock list-foundation-models --region $AWS_REGION &>/dev/null; then
        print_success "Access to Bedrock: Verified"
    else
        print_warning "Access to Bedrock: Not verified"
    fi

    # Add a note about required permissions
    if aws iam get-role --role-name EC2-Dev-Role &>/dev/null; then
        print_info "Using EC2 instance role: EC2-Dev-Role"
        print_info "Please ensure the role has necessary permissions for EKS, ECR, and Bedrock services"
    fi
}


# Main function
main() {
    print_section "Starting Prerequisites Installation for Amazon Linux"

    # Detect Amazon Linux version
    detect_amazon_linux_version

    # Setup AWS Region
    setup_aws_region

    # Check system requirements
    check_system_requirements || exit 1

    # Check AWS endpoints
    check_aws_endpoints || exit 1

    # Install basic tools
    check_and_install_basic_tools || exit 1

    # Install main components
    install_docker || exit 1
    install_kubectl || exit 1
    install_eksctl || exit 1

    # Verify AWS configuration
    check_ec2_role
    verify_aws_configuration

    print_section "Installation Complete"
    print_success "All prerequisites have been installed and verified"

    if groups | grep -q docker; then
        print_success "Docker group permissions are properly configured"
    else
        print_warning "To use Docker without sudo, run: 'newgrp docker' or start a new session"
    fi

    # Print summary
    print_section "Installation Summary"
    print_info "Amazon Linux Version: $AMAZON_LINUX_VERSION"
    print_info "Architecture: $(uname -m)"
    print_info "AWS Region: $AWS_REGION"
    print_info "Docker Version: $(docker --version 2>/dev/null || echo 'Not installed')"
    print_info "kubectl Version: $(kubectl version --client 2>/dev/null || echo 'Not installed')"
    print_info "eksctl Version: $(eksctl version 2>/dev/null || echo 'Not installed')"

}

# Execute main function
main

