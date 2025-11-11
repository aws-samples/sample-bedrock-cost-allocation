"""
CloudWatch Helper for Amazon Bedrock Application Inference Profile (AIP) Monitoring

This module provides functions to fetch and visualize CloudWatch metrics for Amazon Bedrock
Application Inference Profiles (AIPs). It supports multi-tenant cost tracking and usage
monitoring by retrieving metrics specific to each AIP.

Key Features:
- Fetches Bedrock runtime metrics: Invocations, InputTokenCount, OutputTokenCount
- Supports Application Inference Profile monitoring for tenant isolation
- Provides visualization capabilities for usage patterns
- Integrates with AWS CloudWatch metrics under 'AWS/Bedrock' namespace

AWS Documentation Reference:
- Bedrock Monitoring: https://docs.aws.amazon.com/bedrock/latest/userguide/monitoring.html
- Inference Profiles: https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles.html
"""

import boto3
import datetime
from datetime import timedelta
import matplotlib.pyplot as plt
from .config import ModelId

def fetch_metrices(Region, Period, Timedelta, Id):
    """
    Fetch CloudWatch metrics for Amazon Bedrock Application Inference Profile.
    
    This function retrieves three key metrics from AWS/Bedrock namespace:
    1. Invocations - Number of successful API calls (InvokeModel, Converse, etc.)
    2. InputTokenCount - Total input tokens processed
    3. OutputTokenCount - Total output tokens generated
    
    Args:
        Region (str): AWS region where the AIP is deployed
        Period (int): Time period for metric aggregation (currently unused, defaults to 60s)
        Timedelta (int): Time range for metrics (currently unused, defaults to 60 minutes)
        Id (str): Application Inference Profile ID (last part of AIP ARN)
                 Note: Use AIP ID, not full ARN, as CloudWatch ModelId dimension
    
    Returns:
        tuple: (invocation_response, input_token_response, output_token_response)
               Each response contains CloudWatch metric datapoints
    
    Note:
        - Metrics are fetched for the last 60 minutes with 1-minute granularity
        - The Id parameter should be the AIP ID (e.g., 'tenant-a-claude-sonnet') 
          not the full ARN, as CloudWatch uses this as the ModelId dimension
        - All metrics use 'Sum' statistic to get total counts/tokens
    """
    
    # Initialize CloudWatch client for the specified region
    # This client will be used to query Bedrock metrics from AWS/Bedrock namespace
    cloudwatch = boto3.client('cloudwatch', region_name=Region)
    
    # Define time range for metric retrieval (last 60 minutes)
    # Using UTC timezone to ensure consistent time handling across regions
    end_time = datetime.datetime.now(datetime.UTC)
    start_time = end_time - timedelta(minutes=60)
    
    # Fetch Bedrock Invocations metric
    # This tracks the number of successful API calls to Bedrock runtime operations:
    # - InvokeModel, InvokeModelWithResponseStream
    # - Converse, ConverseStream
    # Metric Name: 'Invocations' (AWS/Bedrock namespace)
    # Dimension: ModelId = Application Inference Profile ID
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/Bedrock',  # AWS Bedrock CloudWatch namespace
        MetricName='Invocations',  # Counts successful runtime API calls
        Dimensions=[
            {
                'Name': 'ModelId',  # Primary dimension for Bedrock metrics
                'Value': Id  # AIP ID (not full ARN) - enables per-tenant tracking
            }
        ],
        StartTime=start_time,  # Query start time (60 minutes ago)
        EndTime=end_time,      # Query end time (now)
        Period=60,             # 1-minute aggregation periods
        Statistics=['Sum']     # Total count of invocations per period
    )
    
    # Display invocation count results
    # Each datapoint represents the total invocations in a 1-minute period
    print("Invocation Count:")
    for datapoint in response['Datapoints']:
        print(f"Time: {datapoint['Timestamp']}, Count: {datapoint['Sum']}")
    
    # Fetch Bedrock InputTokenCount metric
    # This tracks the total number of input tokens processed by the model
    # Essential for cost calculation and usage monitoring in multi-tenant scenarios
    # Metric Name: 'InputTokenCount' (AWS/Bedrock namespace)
    input_token_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/Bedrock',      # AWS Bedrock CloudWatch namespace
        MetricName='InputTokenCount', # Tracks input tokens consumed
        Dimensions=[
            {
                'Name': 'ModelId',    # Dimension for per-AIP tracking
                'Value': Id           # AIP ID enables tenant-specific monitoring
            }
        ],
        StartTime=start_time,         # Same time range as invocations
        EndTime=end_time,
        Period=60,                    # 1-minute granularity
        Statistics=['Sum']            # Total input tokens per period
    )
    
    # Display input token count results
    # Shows token consumption patterns for cost analysis and capacity planning
    print("\nInput Token Count:")
    for datapoint in input_token_response['Datapoints']:
        print(f"Time: {datapoint['Timestamp']}, Tokens: {datapoint['Sum']}")
    
    # Fetch Bedrock OutputTokenCount metric
    # This tracks the total number of output tokens generated by the model
    # Critical for understanding model response patterns and billing
    # Metric Name: 'OutputTokenCount' (AWS/Bedrock namespace)
    output_token_response = cloudwatch.get_metric_statistics(
        Namespace='AWS/Bedrock',       # AWS Bedrock CloudWatch namespace
        MetricName='OutputTokenCount', # Tracks output tokens generated
        Dimensions=[
            {
                'Name': 'ModelId',     # Dimension for per-AIP tracking
                'Value': Id            # AIP ID for tenant-specific monitoring
            }
        ],
        StartTime=start_time,          # Consistent time range
        EndTime=end_time,
        Period=60,                     # 1-minute granularity
        Statistics=['Sum']             # Total output tokens per period
    )
    
    # Display output token count results
    # Essential for understanding model generation patterns and costs
    print("\nOutput Token Count:")
    for datapoint in output_token_response['Datapoints']:
        print(f"Time: {datapoint['Timestamp']}, Tokens: {datapoint['Sum']}")

    # Return all three metric responses for visualization
    # These can be used by plot_graph() or other analysis functions
    return response, input_token_response, output_token_response

def plot_graph(response, input_token_response, output_token_response):
    """
    Create visualization charts for Bedrock Application Inference Profile metrics.
    
    This function generates a 3-panel time series plot showing:
    1. Invocations over time - API call frequency patterns
    2. Input Token Count over time - Request complexity trends  
    3. Output Token Count over time - Response generation patterns
    
    Args:
        response: CloudWatch response for Invocations metric
        input_token_response: CloudWatch response for InputTokenCount metric  
        output_token_response: CloudWatch response for OutputTokenCount metric
    
    Features:
        - Time-sorted data points for accurate trend visualization
        - Color-coded charts (blue, green, red) for easy differentiation
        - Grid lines for better readability
        - Markers on data points to highlight individual measurements
        - Tight layout for optimal space utilization
    
    Use Cases:
        - Multi-tenant usage pattern analysis
        - Cost monitoring and forecasting
        - Performance trend identification
        - Capacity planning for AIP scaling
    """
    # Create subplot layout: 3 rows, 1 column, with specified figure size
    # This layout stacks the three metrics vertically for easy comparison
    fig, axes = plt.subplots(3, 1, figsize=(12, 10))

    # Plot Invocations metric (top panel)
    # Sort datapoints by timestamp to ensure proper time series visualization
    inv_data = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])
    inv_times = [dp['Timestamp'] for dp in inv_data]
    inv_values = [dp['Sum'] for dp in inv_data]
    # Blue line with circular markers, thicker line for visibility
    axes[0].plot(inv_times, inv_values, marker='o', linewidth=2)
    axes[0].set_title('Invocations over 1 hour')  # Clear title for API call tracking
    axes[0].set_ylabel('Count')                   # Y-axis shows number of calls
    axes[0].grid(True)                           # Grid for easier value reading
    
    # Plot Input Token Count metric (middle panel)
    # Shows the volume of input tokens processed - indicates request complexity
    input_data = sorted(input_token_response['Datapoints'], key=lambda x: x['Timestamp'])
    input_times = [dp['Timestamp'] for dp in input_data]
    input_values = [dp['Sum'] for dp in input_data]
    # Green line to distinguish from invocations, represents input complexity
    axes[1].plot(input_times, input_values, marker='o', color='green', linewidth=2)
    axes[1].set_title('Input Token Count over 1 hour')  # Tracks request token usage
    axes[1].set_ylabel('Tokens')                        # Y-axis shows token count
    axes[1].grid(True)                                  # Grid for value reference
    
    # Plot Output Token Count metric (bottom panel)  
    # Shows the volume of output tokens generated - indicates response complexity
    output_data = sorted(output_token_response['Datapoints'], key=lambda x: x['Timestamp'])
    output_times = [dp['Timestamp'] for dp in output_data]
    output_values = [dp['Sum'] for dp in output_data]
    # Red line to distinguish from other metrics, represents output generation
    axes[2].plot(output_times, output_values, marker='o', color='red', linewidth=2)
    axes[2].set_title('Output Token Count over 1 hour') # Tracks response token usage
    axes[2].set_ylabel('Tokens')                        # Y-axis shows token count
    axes[2].grid(True)                                  # Grid for value reference
    
    # Optimize layout and display the complete visualization
    # tight_layout() prevents overlapping labels and titles
    plt.tight_layout()
    plt.show()  # Display the interactive plot
