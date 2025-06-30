# Amazon Bedrock Application Inference Profile Setup Workshop

This guide provides step-by-step instructions for setting up an Amazon EKS cluster with a public Network Load Balancer (NLB) and Bedrock integration.

## Directory Structure Update

The project has been reorganized to use a more structured directory layout. All EKS deployment resources are now located in the `eks-deployment` directory:

```
sample-bedrock-cost-allocation/
├── README.md
├── app/                                   # Application source code
│   ├── app.py                            # Main Flask application
│   ├── Dockerfile                        # Container configuration
│   ├── requirements.txt                  # Python dependencies
├── eks-deployment/                       # EKS deployment resources
│   ├── cluster/                          # EKS cluster configurations
│   │   ├── eks-console-access.yaml       # Console access RBAC
│   │   └── inference-poc-clusterconfig.yaml # Main cluster config
│   │
│   ├── k8s/                              # Kubernetes manifests
│   │   ├── crds.yaml                     # AWS Load Balancer Controller CRDs
│   │   ├── inferenceapp-amd64.yaml       # Application deployment for AMD64
│   │   ├── inferenceapp-arm64.yaml       # Application deployment for ARM64
│   │   └── inferencepoc-service.yaml     # NLB service configuration
│   │
│   └── README.md                         # EKS deployment documentation
│
├── iam/                                  # IAM policies and roles
│   ├── bedrockpolicypoc.json             # Bedrock access policy
│   ├── dynamodbpolicypoc.json            # DynamoDB access policy
│   ├── eks-console-policy.json           # EKS console access policy
│   └── iam_policy.json                   # Load Balancer Controller policy
│
└── scripts/                              # Deployment and management scripts
    ├── 00-install-eks-prerequisites.sh   # Install required tools
    ├── 01-validate-configs.sh            # Validate configurations
    ├── 02-create-resources.sh            # Create EKS cluster and DynamoDB table
    ├── 03-create-service-account.sh      # Set up service accounts
    ├── 04-setup-console-access.sh        # Configure console access
    ├── 05-setup-vpc-peering.sh           # Setup VPC peering
    ├── 06-buildimage.sh                  # Build and push Docker image
    ├── 07-deploy-app.sh                  # Deploy application
    ├── 09-cleanup.sh                     # Clean up resources
    ├── team-profile-client.sh            # Client script to consume the service on EKS
    └── config.env                        # Configuration file
```

**Note:** All scripts have been updated to use the new directory structure. The previous duplicate directories (`cluster-duplicate` and `k8s-duplicate`) are no longer needed and can be safely removed.


# EKS Deployment with Bedrock Integration

This repository contains the infrastructure and application code for deploying a Flask application on Amazon EKS with Bedrock integration and public Network Load Balancer setup.

## Project Structure
```
eks-deployment/
├── cluster/               # Cluster configuration files
├── app/                  # Application source code
├── k8s/                 # Kubernetes manifests
├── iam/                 # IAM policies
└── scripts/             # Deployment scripts
```

## Prerequisites


    AWS CLI configured with appropriate permissions
    eksctl installed
    kubectl installed (>= 1.32)
    Docker installed
    Python 3.11+
    AWS Account with Bedrock access
    Minimum 4GB RAM
    8GB free disk space
    AWS Account with Bedrock access

## Quick Start

1. Clone the repository:
```bash
git clone <repository-url>
cd eks-deployment
```

2. Export your AWS Account ID:
```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

3. Install prerequisites:
```bash
./scripts/00-install-eks-prerequisites.sh
```
    
4. Validate configurations:
```bash
./scripts/01-validate-configs.sh
```
    

5. Deploy the infrastructure:
```bash
./scripts/02-create-resources.sh
./scripts/03-create-service-account.sh
./scripts/04-setup-console-access.sh
```

4. Build and deploy application:
```bash
./scripts/05-buildimage.sh
./scripts/06-deploy-app.sh
```

## Components

### 1. EKS Cluster
- Region: us-west-2
- Kubernetes version: 1.32
- Node types: 
  - Primary: m5.large

### 2. Flask Application
- Python 3.11
- AWS Bedrock integration
- Health check endpoints
- Team A/B endpoints
- Error handling

### 3. Network Load Balancer
- Internet-facing
- TCP port 80
- Dynamic target group registration

## Deployment Details

### 1. Prerequisites Installation
Ensure all required tools are installed:
```bash
./scripts/00-install-eks-prerequisites.sh
```

### Creating the resources
```bash
./scripts/02-create-resources.sh
```

This script:

Creates EKS cluster using inference-poc-clusterconfig.yaml
Sets up managed node groups with m8g.medium instances
Configures necessary VPC and networking components
Updates your kubeconfig file
It also creates DynamoDB table team-profile.


### Setting up IAM and Service Accounts
```bash
./scripts/03-create-service-account.sh
```

This creates:

AWS Load Balancer Controller IAM policy
Service account inferencepoc-sa
Bedrock access policy
Necessary IAM role bindings

### Setting up Console Access (Optional)
```bash
./scripts/04-setup-console-access.sh
```

### Building and Pushing the Container Image
```bash
./scripts/05-buildimage.sh
```

This script:

Creates ECR repository if it doesn't exist
Builds Docker image from app directory
Tags and pushes image to ECR

### Deploying the Application
```bash
./scripts/06-deploy-app.sh
```

## Monitoring

Checking Service Status:

```bash
# Get service URL
kubectl get svc inferencepoc-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Check deployment status
kubectl get deployments inferencepoc-deployment

# View pod status
kubectl get pods -l app=inferencepoc

```

## Testing Endpoints
```bash
# Store service URL in variable
export SERVICE_URL=$(kubectl get svc inferencepoc-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test health endpoint
curl http://${SERVICE_URL}/hello

# Test Bedrock health
curl http://${SERVICE_URL}/bedrock-health

```

## Viewing Logs
```bash
# View logs from all pods
kubectl logs -l app=inferencepoc

# View logs from a specific pod
kubectl logs $(kubectl get pod -l app=inferencepoc -o jsonpath='{.items[0].metadata.name}')

# Stream logs
kubectl logs -f -l app=inferencepoc

```


## Cleanup

To remove all resources:
```bash
./scripts/07-cleanup.sh
```

## Consumer
```bash
./scripts/team-profile-client.sh
```
-----
Usage:
Welcome to Team Profile API Client
=================================
Available actions:
-----------------
- create
- delete
- get
- use

Enter action: use

Valid teams: teama teamb
Enter team tag: teama
Enter version (e.g., 1.0): 1.0
-----


## Security Considerations

- IAM roles use least privilege principle
- Network Load Balancer is configured for public access
- Service account permissions are scoped to necessary resources
- Container runs with limited resources

## Troubleshooting

1. Cluster Creation Issues
   - Verify AWS credentials
   - Check VPC limits
   - Ensure sufficient quota for instance types

2. Application Deployment Issues
   - Check pod logs: `kubectl logs -l app=inferencepoc`
   - Verify service account permissions
   - Check NLB health checks

3. Bedrock Integration Issues
   - Verify Bedrock access permissions
   - Check STS role assumption
   - Validate API quotas

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License

## Support

For support, please open an GitHub issue or contact the maintenance team.

