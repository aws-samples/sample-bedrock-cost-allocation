# Application Inference Profiles Workshop

## Overview

In today's AI-driven world, organizations are building multi-tenant SaaS platforms that serve hundreds or thousands of customers using shared AI models. While this approach maximizes efficiency, it creates a critical challenge: **how do you track, monitor, and bill AI model usage per tenant when everyone shares the same underlying model?**

This workshop teaches you how **Application Inference Profiles (AIP)** solve this fundamental multi-tenancy challenge, enabling you to build scalable, tenant-aware AI applications with granular visibility and control.

> [!IMPORTANT]
> This workshop demonstrates Application Inference Profiles concepts and implementation patterns for multi-tenant AI applications. Examples are for educational purposes and should be adapted for production environments.

## The Multi-Tenant AI Challenge

### **The Problem: Invisible Tenant Usage**

Imagine you're running a SaaS platform with 1,000 enterprise customers, all using AI-powered features through the same Claude model. With traditional **System Inference Profiles**, you face these critical challenges:

**🔍 Visibility Gap:**
- Cannot track which tenant generated which model requests
- No way to measure per-tenant model usage or costs
- Impossible to identify high-usage customers or usage patterns

**💰 Billing Nightmare:**
- Cannot allocate AI costs to specific customers
- No data for usage-based pricing models
- Difficult to justify AI infrastructure investments

**📊 Performance Blindness:**
- Cannot monitor model performance per tenant
- No way to detect if one tenant is affecting others
- Impossible to provide tenant-specific SLAs

**🚫 Control Limitations:**
- Cannot implement per-tenant rate limiting
- No way to prioritize requests by customer tier
- Difficult to implement tenant-specific model configurations

### **The Solution: Application Inference Profiles**

**Application Inference Profiles (AIP)** transform your multi-tenant AI architecture by providing:

- **Tenant-Aware Model Access**: Every request is tagged with tenant context
- **Granular Metrics**: Per-tenant usage, latency, and cost tracking
- **Flexible Controls**: Tenant-specific rate limits, priorities, and configurations
- **Accurate Billing**: Precise cost allocation for usage-based pricing
- **Performance Monitoring**: SLA compliance tracking per tenant

## What You'll Learn

By the end of this workshop, you'll master:

### **🎯 Core AIP Concepts**
- Understanding the limitations of System Inference Profiles in multi-tenant scenarios
- How Application Inference Profiles enable tenant-aware AI applications
- AIP architecture patterns and best practices for scalable multi-tenant systems

### **🛠️ Hands-On Implementation**
- Creating, managing, and monitoring Application Inference Profiles
- Implementing AIP across popular AI frameworks (LangChain, LangGraph, Strands, LiteLLM)
- Building tenant-aware applications with granular metrics and controls

### **📈 Production Deployment**
- Deploying AIP-enabled applications to production with AgentCore Runtime
- Setting up comprehensive monitoring, alerting, and observability
- Implementing auto-scaling and load balancing for multi-tenant AI workloads

### **💡 Real-World Skills**
- Designing multi-tenant AI architectures that scale
- Implementing accurate usage-based billing for AI services
- Building tenant-aware monitoring and alerting systems
- Optimizing AI costs and performance across multiple tenants

## What You'll Build

A complete multi-tenant AI application that evolves from basic System Inference Profiles to sophisticated Application Inference Profiles across multiple frameworks, culminating in production deployment.

## Workshop Journey

### **Lab 1: The Multi-Tenant Metrics Problem**
Understand the limitations of System Inference Profiles in multi-tenant scenarios:
- Shared model usage without tenant visibility
- Inability to track per-tenant costs and performance
- Challenges in implementing tenant-specific policies

**What you'll learn:** Why System Inference Profiles aren't sufficient for multi-tenant applications

### **Lab 2: AIP Solution and CRUD Operations**
Discover how AIP solves multi-tenant challenges and master lifecycle management:
- Tenant-aware model access and metrics
- Per-tenant cost tracking and billing
- Create, read, update, delete AIP configurations
- Tag management for organization and billing
- Monitoring and alerting setup

**What you'll learn:** AIP benefits, core concepts, and hands-on operations

### **Lab 3: AIP with Boto3**
Implement Application Inference Profiles using direct AWS SDK calls:
- Configure boto3 with AIP-enabled models
- Direct model invocations with tenant context
- Track usage and costs per tenant
- Monitor performance with native AWS APIs

**What you'll learn:** Direct boto3 + AIP integration patterns

### **Lab 4: AIP with Strands Agents**
Create tenant-aware agent applications using Strands:
- Configure Strands agents with AIP
- Implement tenant-specific agent behaviors
- Track agent interactions per tenant
- Monitor agent performance and costs

**What you'll learn:** Strands + AIP for agent applications

### **Lab 5: AIP with LiteLLM AI Gateway (Optional)**
Implement AIP through LiteLLM for unified model access:
- Configure LiteLLM gateway with AIP
- Route requests based on tenant context
- Implement fallback and load balancing
- Monitor gateway performance per tenant

**What you'll learn:** LiteLLM + AIP for gateway patterns

### **Lab 6: AIP with LangChain (Optional)**
Implement Application Inference Profiles in LangChain applications:
- Configure LangChain with AIP-enabled models
- Track chain execution per tenant
- Implement tenant-aware prompt templates
- Monitor LangChain performance by tenant

**What you'll learn:** LangChain + AIP integration patterns

### **Lab 7: AIP with LangGraph (Optional)**
Build multi-tenant graph-based applications with AIP:
- Configure LangGraph workflows with AIP
- Track graph execution across tenants
- Implement tenant-specific graph configurations
- Monitor complex workflow performance

**What you'll learn:** LangGraph + AIP for complex workflows

## Prerequisites

- AWS account with Bedrock access
- Python 3.10+
- AWS CLI configured
- Claude 3.7 Sonnet enabled in Bedrock
- Basic understanding of AI/ML concepts

## Architecture Evolution

Watch your application evolve from basic shared models to sophisticated multi-tenant architecture:

**Lab 1:** System Inference Profiles → Multi-tenant metrics challenges

**Lab 2:** Application Inference Profiles + CRUD → Tenant-aware model access and management

**Lab 3:** Boto3 Integration → Direct AWS SDK implementation

**Lab 4:** Strands Integration → Agent applications with AIP

**Labs 5-7:** Optional Framework Integrations → LiteLLM, LangChain & LangGraph

## Business Context: Meet Alex, Platform Engineer

Throughout this workshop, you'll follow **Alex, Platform Engineer at CloudTech Solutions**, a SaaS platform serving multiple enterprise customers. Alex needs to:

- **Track model usage** per customer for accurate billing
- **Monitor performance** by tenant to ensure SLA compliance
- **Implement controls** to prevent one tenant from affecting others
- **Scale efficiently** while maintaining tenant isolation
- **Deploy reliably** to production with full observability

Each lab addresses a specific challenge in Alex's multi-tenant AI platform journey.

## Getting Started

1. Clone this repository
2. Install dependencies: `pip install -r requirements.txt`
3. Configure AWS credentials
4. Run setup script: `./scripts/setup_environment.sh`
5. Start with [Lab 1](lab-01-system-inference-problem.ipynb)

Each lab builds on the previous one, demonstrating progressive enhancement of your multi-tenant AI platform.

## Key Concepts Covered

### **Application Inference Profiles**
- Tenant-aware model access
- Per-tenant metrics and billing
- Granular performance monitoring
- Tenant-specific controls and policies

### **Framework Integration**
- LangChain: Chain-based applications with AIP
- LangGraph: Graph workflows with tenant awareness
- Strands: Agent applications with AIP
- LiteLLM: Gateway patterns with AIP

## Workshop Structure

```
├── Lab 1: Problem Statement (System Inference Profiles limitations)
├── Lab 2: Solution & Management (AIP benefits, concepts, and CRUD operations)
├── Lab 3: Boto3 Implementation (Direct AWS SDK integration)
├── Lab 4: Strands Implementation (Agent applications with AIP)
├── Lab 5: LiteLLM Implementation - Optional (Gateway patterns with AIP)
├── Lab 6: LangChain Implementation - Optional (Chain-based applications)
└── Lab 7: LangGraph Implementation - Optional (Graph workflows)
```

## Resources

- [Application Inference Profiles Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles.html)
- [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/)
- [Multi-Tenant Architecture Best Practices](https://aws.amazon.com/architecture/multi-tenant/)

Ready to solve multi-tenant AI challenges? [Start with Lab 1 →](lab-01-system-inference-problem.ipynb)
