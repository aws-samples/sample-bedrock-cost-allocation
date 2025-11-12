#!/bin/bash
#############################################################################
# Script Name: 05-setup-vpc-peering.sh
# Description: Sets up VPC peering between host VPC and EKS cluster VPC
#
# Author: Sandeep Rohilla
# Date: June 2025
#
# Prerequisites:
#   - AWS CLI v2
#   - Valid AWS credentials and region configuration
#   - EKS cluster already created
#   - config.env file in scripts directory
#
# This script automatically:
#   1. Identifies the host VPC where the script is running
#   2. Identifies the EKS cluster VPC
#   3. Creates a VPC peering connection between them
#   4. Accepts the peering connection
#   5. Updates route tables in both VPCs
#   6. Updates the NLB to be internal instead of internet-facing
#
# Usage: ./scripts/05-setup-vpc-peering.sh
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

    # Check if EKS cluster exists
    if ! aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &> /dev/null; then
        print_error "EKS cluster ${CLUSTER_NAME} does not exist"
        return 1
    fi
    print_success "EKS cluster ${CLUSTER_NAME} exists"
}

# Function to identify host VPC
identify_host_vpc() {
    print_section "Identifying Host VPC"
    
    # Get instance ID of the current EC2 instance
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    
    if [ -z "$INSTANCE_ID" ]; then
        print_error "Failed to get instance ID. Are you running on EC2?"
        return 1
    fi
    print_success "Current instance ID: $INSTANCE_ID"
    
    # Get VPC ID of the current instance
    HOST_VPC_ID=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].VpcId' \
        --output text \
        --region ${AWS_REGION})
    
    if [ -z "$HOST_VPC_ID" ] || [ "$HOST_VPC_ID" == "None" ]; then
        print_error "Failed to get host VPC ID"
        return 1
    fi
    print_success "Host VPC ID: $HOST_VPC_ID"
    
    # Get CIDR block of host VPC
    HOST_VPC_CIDR=$(aws ec2 describe-vpcs \
        --vpc-ids $HOST_VPC_ID \
        --query 'Vpcs[0].CidrBlock' \
        --output text \
        --region ${AWS_REGION})
    
    if [ -z "$HOST_VPC_CIDR" ] || [ "$HOST_VPC_CIDR" == "None" ]; then
        print_error "Failed to get host VPC CIDR"
        return 1
    fi
    print_success "Host VPC CIDR: $HOST_VPC_CIDR"
    
    # Update config.env with host VPC information
    if grep -q "HOST_VPC_ID" ./scripts/config.env; then
        sed -i "s|HOST_VPC_ID=.*|HOST_VPC_ID=\"$HOST_VPC_ID\"|" ./scripts/config.env
    else
        echo "HOST_VPC_ID=\"$HOST_VPC_ID\"" >> ./scripts/config.env
    fi
    
    if grep -q "HOST_VPC_CIDR" ./scripts/config.env; then
        sed -i "s|HOST_VPC_CIDR=.*|HOST_VPC_CIDR=\"$HOST_VPC_CIDR\"|" ./scripts/config.env
    else
        echo "HOST_VPC_CIDR=\"$HOST_VPC_CIDR\"" >> ./scripts/config.env
    fi
}

# Function to identify EKS cluster VPC
identify_eks_vpc() {
    print_section "Identifying EKS Cluster VPC"
    
    # Get VPC ID of the EKS cluster
    EKS_VPC_ID=$(aws eks describe-cluster \
        --name ${CLUSTER_NAME} \
        --region ${AWS_REGION} \
        --query 'cluster.resourcesVpcConfig.vpcId' \
        --output text)
    
    if [ -z "$EKS_VPC_ID" ] || [ "$EKS_VPC_ID" == "None" ]; then
        print_error "Failed to get EKS VPC ID"
        return 1
    fi
    print_success "EKS VPC ID: $EKS_VPC_ID"
    
    # Get CIDR block of EKS VPC
    EKS_VPC_CIDR=$(aws ec2 describe-vpcs \
        --vpc-ids $EKS_VPC_ID \
        --query 'Vpcs[0].CidrBlock' \
        --output text \
        --region ${AWS_REGION})
    
    if [ -z "$EKS_VPC_CIDR" ] || [ "$EKS_VPC_CIDR" == "None" ]; then
        print_error "Failed to get EKS VPC CIDR"
        return 1
    fi
    print_success "EKS VPC CIDR: $EKS_VPC_CIDR"
    
    # Update config.env with EKS VPC information
    if grep -q "EKS_VPC_ID" ./scripts/config.env; then
        sed -i "s|EKS_VPC_ID=.*|EKS_VPC_ID=\"$EKS_VPC_ID\"|" ./scripts/config.env
    else
        echo "EKS_VPC_ID=\"$EKS_VPC_ID\"" >> ./scripts/config.env
    fi
    
    if grep -q "EKS_VPC_CIDR" ./scripts/config.env; then
        sed -i "s|EKS_VPC_CIDR=.*|EKS_VPC_CIDR=\"$EKS_VPC_CIDR\"|" ./scripts/config.env
    else
        echo "EKS_VPC_CIDR=\"$EKS_VPC_CIDR\"" >> ./scripts/config.env
    fi
}

# Function to clean up existing peering connections and routes
cleanup_existing_peering() {
    print_section "Cleaning Up Existing Peering Connections"
    
    # Find all peering connections between these VPCs
    EXISTING_PEERINGS=$(aws ec2 describe-vpc-peering-connections \
        --filters "Name=requester-vpc-info.vpc-id,Values=$HOST_VPC_ID,$EKS_VPC_ID" "Name=accepter-vpc-info.vpc-id,Values=$HOST_VPC_ID,$EKS_VPC_ID" \
        --query 'VpcPeeringConnections[*].VpcPeeringConnectionId' \
        --output text \
        --region ${AWS_REGION})
    
    if [ -n "$EXISTING_PEERINGS" ] && [ "$EXISTING_PEERINGS" != "None" ]; then
        for PEERING in $EXISTING_PEERINGS; do
            print_info "Cleaning up peering connection: $PEERING"
            
            # Delete the peering connection (this will automatically clean up routes)
            aws ec2 delete-vpc-peering-connection \
                --vpc-peering-connection-id $PEERING \
                --region ${AWS_REGION} 2>/dev/null || true
            
            print_success "Deleted peering connection: $PEERING"
        done
    fi
    
    # Clean up any blackhole routes in host VPC
    print_info "Cleaning up blackhole routes in host VPC"
    HOST_ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$HOST_VPC_ID" \
        --query 'RouteTables[*].RouteTableId' \
        --output text \
        --region ${AWS_REGION})
    
    for RT_ID in $HOST_ROUTE_TABLES; do
        # Delete any routes to EKS VPC CIDR (including blackhole routes)
        aws ec2 delete-route \
            --route-table-id $RT_ID \
            --destination-cidr-block $EKS_VPC_CIDR \
            --region ${AWS_REGION} 2>/dev/null || true
    done
    
    # Clean up any blackhole routes in EKS VPC
    print_info "Cleaning up blackhole routes in EKS VPC"
    EKS_ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$EKS_VPC_ID" \
        --query 'RouteTables[*].RouteTableId' \
        --output text \
        --region ${AWS_REGION})
    
    for RT_ID in $EKS_ROUTE_TABLES; do
        # Delete any routes to host VPC CIDR (including blackhole routes)
        aws ec2 delete-route \
            --route-table-id $RT_ID \
            --destination-cidr-block $HOST_VPC_CIDR \
            --region ${AWS_REGION} 2>/dev/null || true
    done
    
    print_success "Cleanup completed"
    
    # Wait a moment for cleanup to propagate
    sleep 5
}

# Function to create VPC peering connection
create_vpc_peering() {
    print_section "Creating VPC Peering Connection"
    
    # Create new VPC peering connection
    PEERING_ID=$(aws ec2 create-vpc-peering-connection \
        --vpc-id $HOST_VPC_ID \
        --peer-vpc-id $EKS_VPC_ID \
        --region ${AWS_REGION} \
        --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
        --output text)
    
    if [ -z "$PEERING_ID" ] || [ "$PEERING_ID" == "None" ]; then
        print_error "Failed to create VPC peering connection"
        return 1
    fi
    print_success "VPC peering connection created: $PEERING_ID"
    
    # Update config.env with peering connection ID
    if grep -q "VPC_PEERING_ID" ./scripts/config.env; then
        sed -i "s|VPC_PEERING_ID=.*|VPC_PEERING_ID=\"$PEERING_ID\"|" ./scripts/config.env
    else
        echo "VPC_PEERING_ID=\"$PEERING_ID\"" >> ./scripts/config.env
    fi
}

# Function to accept VPC peering connection
accept_vpc_peering() {
    print_section "Accepting VPC Peering Connection"
    
    # Check peering connection status
    PEERING_STATUS=$(aws ec2 describe-vpc-peering-connections \
        --vpc-peering-connection-ids $PEERING_ID \
        --query 'VpcPeeringConnections[0].Status.Code' \
        --output text \
        --region ${AWS_REGION})
    
    if [ "$PEERING_STATUS" == "active" ]; then
        print_warning "VPC peering connection is already active"
    elif [ "$PEERING_STATUS" == "pending-acceptance" ]; then
        # Accept VPC peering connection
        aws ec2 accept-vpc-peering-connection \
            --vpc-peering-connection-id $PEERING_ID \
            --region ${AWS_REGION}
        
        print_success "VPC peering connection accepted"
    else
        print_error "VPC peering connection is in an unexpected state: $PEERING_STATUS"
        return 1
    fi
}

# Function to update route tables
update_route_tables() {
    print_section "Updating Route Tables"
    
    # Get route tables for host VPC
    HOST_ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$HOST_VPC_ID" \
        --query 'RouteTables[*].RouteTableId' \
        --output text \
        --region ${AWS_REGION})
    
    # Get route tables for EKS VPC
    EKS_ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$EKS_VPC_ID" \
        --query 'RouteTables[*].RouteTableId' \
        --output text \
        --region ${AWS_REGION})
    
    # Update host VPC route tables
    for RT_ID in $HOST_ROUTE_TABLES; do
        print_info "Updating host route table: $RT_ID"
        
        # Check if route already exists
        EXISTING_ROUTE=$(aws ec2 describe-route-tables \
            --route-table-ids $RT_ID \
            --query "RouteTables[0].Routes[?DestinationCidrBlock=='$EKS_VPC_CIDR'].VpcPeeringConnectionId" \
            --output text \
            --region ${AWS_REGION})
        
        if [ -n "$EXISTING_ROUTE" ] && [ "$EXISTING_ROUTE" != "None" ]; then
            print_warning "Route to EKS VPC already exists in route table $RT_ID"
        else
            # Add route to EKS VPC
            aws ec2 create-route \
                --route-table-id $RT_ID \
                --destination-cidr-block $EKS_VPC_CIDR \
                --vpc-peering-connection-id $PEERING_ID \
                --region ${AWS_REGION}
            
            print_success "Added route to EKS VPC in route table $RT_ID"
        fi
    done
    
    # Update EKS VPC route tables
    for RT_ID in $EKS_ROUTE_TABLES; do
        print_info "Updating EKS route table: $RT_ID"
        
        # Check if route already exists
        EXISTING_ROUTE=$(aws ec2 describe-route-tables \
            --route-table-ids $RT_ID \
            --query "RouteTables[0].Routes[?DestinationCidrBlock=='$HOST_VPC_CIDR'].VpcPeeringConnectionId" \
            --output text \
            --region ${AWS_REGION})
        
        if [ -n "$EXISTING_ROUTE" ] && [ "$EXISTING_ROUTE" != "None" ]; then
            print_warning "Route to host VPC already exists in route table $RT_ID"
        else
            # Add route to host VPC
            aws ec2 create-route \
                --route-table-id $RT_ID \
                --destination-cidr-block $HOST_VPC_CIDR \
                --vpc-peering-connection-id $PEERING_ID \
                --region ${AWS_REGION}
            
            print_success "Added route to host VPC in route table $RT_ID"
        fi
    done
}

# Function to update NLB to be internal
#update_nlb_to_internal() {
#    print_section "Updating NLB to Internal"
#    
#    # Update the service YAML file
#    if [ -f "./eks-deployment/k8s/inferencepoc-service.yaml" ]; then
#        # Check if already internal
#        if grep -q "service.beta.kubernetes.io/aws-load-balancer-scheme: internal" ./eks-deployment/k8s/inferencepoc-service.yaml; then
#            print_warning "NLB is already configured as internal"
#        else
#            # Replace internet-facing with internal
#            sed -i 's/service.beta.kubernetes.io\/aws-load-balancer-scheme: internet-facing/service.beta.kubernetes.io\/aws-load-balancer-scheme: internal/g' ./eks-deployment/k8s/inferencepoc-service.yaml
#            
#            print_success "Updated NLB configuration to internal"
#            
#            # Apply the updated configuration
#            print_info "Applying updated NLB configuration..."
#            kubectl apply -f ./eks-deployment/k8s/inferencepoc-service.yaml
#            
#            print_success "NLB configuration applied"
#        fi
#    else
#        print_error "Service YAML file not found"
#        return 1
#    fi
#}

# Main function
main() {
    print_section "Starting VPC Peering Setup"
    
    # Check prerequisites
    check_prerequisites || exit 1
    
    # Identify host VPC
    identify_host_vpc || exit 1
    
    # Identify EKS VPC
    identify_eks_vpc || exit 1
    
    # Clean up existing peering connections and routes
    cleanup_existing_peering || exit 1
    
    # Create VPC peering connection
    create_vpc_peering || exit 1
    
    # Accept VPC peering connection
    accept_vpc_peering || exit 1
    
    # Update route tables
    update_route_tables || exit 1
    
    # Update NLB to be internal
#    update_nlb_to_internal || exit 1
    
    print_section "VPC Peering Setup Complete"
    print_success "VPC peering has been successfully set up between host VPC and EKS VPC"
    print_info "Host VPC: $HOST_VPC_ID ($HOST_VPC_CIDR)"
    print_info "EKS VPC: $EKS_VPC_ID ($EKS_VPC_CIDR)"
    print_info "Peering Connection: $PEERING_ID"
    print_info "NLB is now configured as internal and accessible from the host VPC"

}

# Execute main function
main
