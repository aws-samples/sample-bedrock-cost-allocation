"""
Usage Tracker - Helper class for tracking AIP usage and costs
"""

import boto3
import json
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
from botocore.exceptions import ClientError


class UsageTracker:
    """Tracks usage metrics and costs for Application Inference Profiles"""
    
    def __init__(self, cloudwatch_client: boto3.client = None):
        self.cloudwatch_client = cloudwatch_client or boto3.client('cloudwatch')
        self.usage_data = []
    
    def extract_usage_from_response(self, response: Dict[str, Any], tenant_id: str, aip_arn: str) -> Dict[str, Any]:
        """
        Extract usage metrics from Bedrock response
        
        Args:
            response: Bedrock invoke_model response
            tenant_id: Tenant identifier
            aip_arn: AIP ARN used for the request
            
        Returns:
            Usage metrics dictionary
        """
        usage_info = {
            'timestamp': datetime.utcnow().isoformat(),
            'tenant_id': tenant_id,
            'aip_arn': aip_arn,
            'input_tokens': 0,
            'output_tokens': 0,
            'total_tokens': 0,
            'latency_ms': 0,
            'request_id': response.get('ResponseMetadata', {}).get('RequestId', ''),
            'model_id': ''
        }
        
        # Extract usage from response metadata if available
        if 'usage' in response:
            usage = response['usage']
            usage_info['input_tokens'] = usage.get('inputTokens', 0)
            usage_info['output_tokens'] = usage.get('outputTokens', 0)
            usage_info['total_tokens'] = usage_info['input_tokens'] + usage_info['output_tokens']
        
        # Extract model ID from response metadata
        if 'modelId' in response:
            usage_info['model_id'] = response['modelId']
        
        # Store usage data
        self.usage_data.append(usage_info)
        
        return usage_info
    
    def get_tenant_usage_summary(self, tenant_id: str) -> Dict[str, Any]:
        """
        Get usage summary for a specific tenant
        
        Args:
            tenant_id: Tenant identifier
            
        Returns:
            Usage summary
        """
        tenant_usage = [u for u in self.usage_data if u['tenant_id'] == tenant_id]
        
        if not tenant_usage:
            return {
                'tenant_id': tenant_id,
                'total_requests': 0,
                'total_input_tokens': 0,
                'total_output_tokens': 0,
                'total_tokens': 0,
                'avg_latency_ms': 0
            }
        
        return {
            'tenant_id': tenant_id,
            'total_requests': len(tenant_usage),
            'total_input_tokens': sum(u['input_tokens'] for u in tenant_usage),
            'total_output_tokens': sum(u['output_tokens'] for u in tenant_usage),
            'total_tokens': sum(u['total_tokens'] for u in tenant_usage),
            'avg_latency_ms': sum(u['latency_ms'] for u in tenant_usage) / len(tenant_usage) if tenant_usage else 0
        }
    
    def get_all_usage_summary(self) -> Dict[str, Any]:
        """
        Get usage summary across all tenants
        
        Returns:
            Overall usage summary
        """
        if not self.usage_data:
            return {
                'total_requests': 0,
                'total_input_tokens': 0,
                'total_output_tokens': 0,
                'total_tokens': 0,
                'unique_tenants': 0,
                'tenant_breakdown': {}
            }
        
        # Get unique tenants
        unique_tenants = set(u['tenant_id'] for u in self.usage_data)
        
        # Calculate tenant breakdown
        tenant_breakdown = {}
        for tenant_id in unique_tenants:
            tenant_breakdown[tenant_id] = self.get_tenant_usage_summary(tenant_id)
        
        return {
            'total_requests': len(self.usage_data),
            'total_input_tokens': sum(u['input_tokens'] for u in self.usage_data),
            'total_output_tokens': sum(u['output_tokens'] for u in self.usage_data),
            'total_tokens': sum(u['total_tokens'] for u in self.usage_data),
            'unique_tenants': len(unique_tenants),
            'tenant_breakdown': tenant_breakdown
        }
    
    def send_metrics_to_cloudwatch(self, namespace: str = "MarketingAI/AIP") -> bool:
        """
        Send usage metrics to CloudWatch
        
        Args:
            namespace: CloudWatch namespace
            
        Returns:
            True if successful
        """
        try:
            # Group metrics by tenant
            tenant_metrics = {}
            for usage in self.usage_data:
                tenant_id = usage['tenant_id']
                if tenant_id not in tenant_metrics:
                    tenant_metrics[tenant_id] = {
                        'requests': 0,
                        'input_tokens': 0,
                        'output_tokens': 0,
                        'total_tokens': 0
                    }
                
                tenant_metrics[tenant_id]['requests'] += 1
                tenant_metrics[tenant_id]['input_tokens'] += usage['input_tokens']
                tenant_metrics[tenant_id]['output_tokens'] += usage['output_tokens']
                tenant_metrics[tenant_id]['total_tokens'] += usage['total_tokens']
            
            # Send metrics to CloudWatch
            for tenant_id, metrics in tenant_metrics.items():
                metric_data = [
                    {
                        'MetricName': 'RequestCount',
                        'Dimensions': [{'Name': 'TenantId', 'Value': tenant_id}],
                        'Value': metrics['requests'],
                        'Unit': 'Count'
                    },
                    {
                        'MetricName': 'InputTokens',
                        'Dimensions': [{'Name': 'TenantId', 'Value': tenant_id}],
                        'Value': metrics['input_tokens'],
                        'Unit': 'Count'
                    },
                    {
                        'MetricName': 'OutputTokens',
                        'Dimensions': [{'Name': 'TenantId', 'Value': tenant_id}],
                        'Value': metrics['output_tokens'],
                        'Unit': 'Count'
                    },
                    {
                        'MetricName': 'TotalTokens',
                        'Dimensions': [{'Name': 'TenantId', 'Value': tenant_id}],
                        'Value': metrics['total_tokens'],
                        'Unit': 'Count'
                    }
                ]
                
                self.cloudwatch_client.put_metric_data(
                    Namespace=namespace,
                    MetricData=metric_data
                )
            
            return True
            
        except ClientError as e:
            print(f"Error sending metrics to CloudWatch: {str(e)}")
            return False
    
    def export_usage_data(self, format: str = "json") -> str:
        """
        Export usage data in specified format
        
        Args:
            format: Export format (json, csv)
            
        Returns:
            Formatted usage data
        """
        if format.lower() == "json":
            return json.dumps(self.usage_data, indent=2, default=str)
        elif format.lower() == "csv":
            if not self.usage_data:
                return "No usage data available"
            
            # Create CSV header
            headers = list(self.usage_data[0].keys())
            csv_lines = [",".join(headers)]
            
            # Add data rows
            for usage in self.usage_data:
                row = [str(usage.get(header, "")) for header in headers]
                csv_lines.append(",".join(row))
            
            return "\n".join(csv_lines)
        else:
            raise ValueError(f"Unsupported format: {format}")
    
    def clear_usage_data(self):
        """Clear stored usage data"""
        self.usage_data = []
