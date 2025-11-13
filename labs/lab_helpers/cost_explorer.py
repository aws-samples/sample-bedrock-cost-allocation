"""
Cost Explorer Helper for Amazon Bedrock Application Inference Profile (AIP) Cost Tracking

This module provides functions to fetch and visualize AWS Cost Explorer data for Amazon Bedrock
costs filtered by Application Inference Profile tags. It enables multi-tenant cost allocation
and billing by retrieving costs specific to each tenant's AIP usage.

Key Features:
- Fetches Bedrock service costs filtered by tag key/value pairs
- Supports per-tenant cost tracking through AIP tags
- Provides visualization capabilities for cost trends
- Integrates with AWS Cost Explorer API for accurate billing data

AWS Documentation Reference:
- Cost Explorer API: https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/
- Bedrock Pricing: https://aws.amazon.com/bedrock/pricing/
"""

import boto3
import datetime
from datetime import timedelta
import matplotlib.pyplot as plt
import pandas as pd
from typing import Dict, List, Optional, Tuple


def fetch_bedrock_costs_by_tag(
    region: str,
    tag_key: str, 
    tag_value: str,
    days_back: int = 30,
    granularity: str = 'DAILY',
    aws_access_key_id: str = None,
    aws_secret_access_key: str = None
) -> Dict:
    """
    Fetch Bedrock costs from Cost Explorer filtered by specific tag key/value.
    
    Args:
        region (str): AWS region (for client initialization)
        tag_key (str): Tag key to filter by (e.g., 'TenantId')
        tag_value (str): Tag value to filter by (e.g., 'tenant-a')
        days_back (int): Number of days to look back for cost data
        granularity (str): Time granularity - 'DAILY' or 'MONTHLY'
        aws_access_key_id (str): AWS access key ID (optional)
        aws_secret_access_key (str): AWS secret access key (optional)
    
    Returns:
        Dict: Cost Explorer response with Bedrock costs for the specified tag
    """
    
    # Initialize Cost Explorer client
    if aws_access_key_id and aws_secret_access_key:
        ce_client = boto3.client(
            'ce', 
            region_name=region,
            aws_access_key_id=aws_access_key_id,
            aws_secret_access_key=aws_secret_access_key
        )
    else:
        ce_client = boto3.client('ce', region_name=region)
    
    # Calculate time range
    end_date = datetime.datetime.now().date()
    start_date = end_date - timedelta(days=days_back)
    
    try:
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity=granularity,
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ],
            Filter={
                'And': [
                    {
                        'Dimensions': {
                            'Key': 'SERVICE',
                            'Values': ['Amazon Bedrock']
                        }
                    },
                    {
                        'Tags': {
                            'Key': tag_key,
                            'Values': [tag_value]
                        }
                    }
                ]
            }
        )
        return response
        
    except Exception as e:
        print(f"Error fetching cost data: {str(e)}")
        return {}


def fetch_all_tenant_costs(
    region: str,
    tenant_ids: List[str],
    days_back: int = 30,
    tag_key: str = 'TenantId',
    aws_access_key_id: str = None,
    aws_secret_access_key: str = None
) -> Dict[str, Dict]:
    """
    Fetch Bedrock costs for multiple tenants.
    
    Args:
        region (str): AWS region
        tenant_ids (List[str]): List of tenant IDs to fetch costs for
        days_back (int): Number of days to look back
        tag_key (str): Tag key used for tenant identification
        aws_access_key_id (str): AWS access key ID (optional)
        aws_secret_access_key (str): AWS secret access key (optional)
    
    Returns:
        Dict[str, Dict]: Costs by tenant ID
    """
    
    tenant_costs = {}
    
    for tenant_id in tenant_ids:
        print(f"Fetching costs for {tenant_id}...")
        costs = fetch_bedrock_costs_by_tag(
            region=region,
            tag_key=tag_key,
            tag_value=tenant_id,
            days_back=days_back,
            aws_access_key_id=aws_access_key_id,
            aws_secret_access_key=aws_secret_access_key
        )
        tenant_costs[tenant_id] = costs
    
    return tenant_costs


def parse_cost_data(cost_response: Dict) -> Tuple[List[str], List[float]]:
    """
    Parse Cost Explorer response into dates and costs.
    
    Args:
        cost_response (Dict): Cost Explorer API response
    
    Returns:
        Tuple[List[str], List[float]]: (dates, costs)
    """
    
    dates = []
    costs = []
    
    if 'ResultsByTime' in cost_response:
        for result in cost_response['ResultsByTime']:
            date = result['TimePeriod']['Start']
            dates.append(date)
            
            # Sum costs across all groups (should be just Bedrock)
            total_cost = 0.0
            for group in result['Groups']:
                if group['Keys'][0] == 'Amazon Bedrock':
                    cost_amount = float(group['Metrics']['BlendedCost']['Amount'])
                    total_cost += cost_amount
            
            costs.append(total_cost)
    
    return dates, costs


def visualize_tenant_costs(
    tenant_costs: Dict[str, Dict],
    title: str = "Bedrock Costs by Tenant"
) -> None:
    """
    Create visualization of costs across multiple tenants.
    
    Args:
        tenant_costs (Dict[str, Dict]): Cost data by tenant
        title (str): Chart title
    """
    
    plt.figure(figsize=(12, 8))
    
    for tenant_id, cost_data in tenant_costs.items():
        dates, costs = parse_cost_data(cost_data)
        
        if dates and costs:
            # Convert dates to datetime for better plotting
            date_objects = [datetime.datetime.strptime(d, '%Y-%m-%d') for d in dates]
            plt.plot(date_objects, costs, marker='o', label=f'{tenant_id}', linewidth=2)
    
    plt.title(title, fontsize=16, fontweight='bold')
    plt.xlabel('Date', fontsize=12)
    plt.ylabel('Cost (USD)', fontsize=12)
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.xticks(rotation=45)
    plt.tight_layout()
    plt.show()


def create_cost_summary_table(tenant_costs: Dict[str, Dict]) -> pd.DataFrame:
    """
    Create a summary table of costs by tenant.
    
    Args:
        tenant_costs (Dict[str, Dict]): Cost data by tenant
    
    Returns:
        pd.DataFrame: Summary table with total costs per tenant
    """
    
    summary_data = []
    
    for tenant_id, cost_data in tenant_costs.items():
        dates, costs = parse_cost_data(cost_data)
        
        if costs:
            total_cost = sum(costs)
            avg_daily_cost = total_cost / len(costs) if costs else 0
            max_daily_cost = max(costs) if costs else 0
            
            summary_data.append({
                'Tenant ID': tenant_id,
                'Total Cost ($)': round(total_cost, 4),
                'Avg Daily Cost ($)': round(avg_daily_cost, 4),
                'Max Daily Cost ($)': round(max_daily_cost, 4),
                'Days with Usage': len([c for c in costs if c > 0])
            })
    
    return pd.DataFrame(summary_data)


def visualize_cost_breakdown(
    tenant_costs: Dict[str, Dict],
    chart_type: str = 'pie'
) -> None:
    """
    Create a cost breakdown visualization (pie chart or bar chart).
    
    Args:
        tenant_costs (Dict[str, Dict]): Cost data by tenant
        chart_type (str): 'pie' or 'bar'
    """
    
    tenant_totals = {}
    
    for tenant_id, cost_data in tenant_costs.items():
        dates, costs = parse_cost_data(cost_data)
        tenant_totals[tenant_id] = sum(costs) if costs else 0
    
    # Filter out tenants with zero costs
    tenant_totals = {k: v for k, v in tenant_totals.items() if v > 0}
    
    if not tenant_totals:
        print("No cost data available for visualization")
        return
    
    plt.figure(figsize=(10, 6))
    
    if chart_type == 'pie':
        plt.pie(tenant_totals.values(), labels=tenant_totals.keys(), autopct='%1.1f%%')
        plt.title('Bedrock Cost Distribution by Tenant', fontsize=16, fontweight='bold')
    else:  # bar chart
        plt.bar(tenant_totals.keys(), tenant_totals.values())
        plt.title('Total Bedrock Costs by Tenant', fontsize=16, fontweight='bold')
        plt.xlabel('Tenant ID', fontsize=12)
        plt.ylabel('Total Cost (USD)', fontsize=12)
        plt.xticks(rotation=45)
    
    plt.tight_layout()
    plt.show()
