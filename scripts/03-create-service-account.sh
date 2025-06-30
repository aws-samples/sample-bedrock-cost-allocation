#!/bin/bash
#############################################################################
# Script Name: 03-create-service-account.sh
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

# Export AWS Account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_info "Using AWS Account ID: ${AWS_ACCOUNT_ID}"

# Setup AWS Region
export AWS_REGION=$(grep "^AWS_REGION=" "./scripts/config.env" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d '[:space:]')
export AWS_DEFAULT_REGION=$AWS_REGION
print_info "Using AWS Region: ${AWS_REGION}"

print_section "Starting Service Account Setup"

# Enable OIDC provider
print_section "Setting up OIDC Provider"
eksctl utils associate-iam-oidc-provider \
    --region ${AWS_REGION} \
    --cluster ${CLUSTER_NAME} \
    --approve

# Create IAM policies
print_section "Creating IAM Policies"

# Load Balancer Controller Policy
print_info "Creating Load Balancer Controller Policy..."
aws iam create-policy \
    --policy-name ${IAM_POLICY_LB_NAME} \
    --policy-document file://./iam/iam_policy.json \
    --description "EKS Load Balancer Controller Policy" 2>/dev/null || true

# Bedrock Policy
print_info "Creating Bedrock Policy..."
aws iam create-policy \
    --policy-name ${IAM_POLICY_BEDROCK_NAME} \
    --policy-document file://./iam/bedrockpolicy.json \
    --description "Bedrock Access Policy" 2>/dev/null || true

# DynamoDB Policy
print_info "Creating DynamoDB Policy..."
aws iam create-policy \
    --policy-name ${IAM_POLICY_DYNAMODB_NAME} \
    --policy-document file://./iam/dynamodbpolicypoc.json \
    --description "DynamoDB Access Policy" 2>/dev/null || true

# Create service account
print_section "Creating Service Account"

# Delete existing service account if it exists
kubectl delete serviceaccount -n ${SERVICE_ACCOUNT_NAMESPACE} ${SERVICE_ACCOUNT_NAME} --ignore-not-found

# Create the service account
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${SERVICE_ACCOUNT_NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}
EOF

# Create IAM role and attach policies
print_info "Creating IAM role for service account..."

OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

TRUST_RELATIONSHIP=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}"
        }
      }
    }
  ]
}
EOF
)

# Check if role exists and update trust policy, otherwise create it
if aws iam get-role --role-name "${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}" &>/dev/null; then
    print_info "Role ${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME} exists, updating trust policy..."
    aws iam update-assume-role-policy \
        --role-name "${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}" \
        --policy-document "$TRUST_RELATIONSHIP"
else
    print_info "Creating role ${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}..."
    aws iam create-role --role-name "${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}" --assume-role-policy-document "$TRUST_RELATIONSHIP"
fi

# Attach policies to role
aws iam attach-role-policy \
    --role-name "${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}" \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_LB_NAME}"

aws iam attach-role-policy \
    --role-name "${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}" \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_BEDROCK_NAME}"

aws iam attach-role-policy \
    --role-name "${CLUSTER_NAME}-${SERVICE_ACCOUNT_NAME}" \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_DYNAMODB_NAME}"

print_success "Service account and IAM role created"

# Verify setup
print_section "Verifying Setup"

# Check service account
if kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -n ${SERVICE_ACCOUNT_NAMESPACE}; then
    print_success "Service account exists"
else
    print_error "Service account creation failed"
    exit 1
fi

# Check role ARN annotation
ROLE_ARN=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -n ${SERVICE_ACCOUNT_NAMESPACE} -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
if [ -n "$ROLE_ARN" ]; then
    print_success "Role ARN annotation found: $ROLE_ARN"
else
    print_error "Role ARN annotation not found"
    exit 1
fi

print_section "Setup Complete"
print_success "Service account setup completed successfully"
