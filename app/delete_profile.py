#!/usr/bin/env python3
"""
Delete profile functionality for AWS Bedrock Inference Profile Management API
"""

import logging
import boto3
from botocore.exceptions import ClientError
from utils import aws_clients, AWS_REGION, DYNAMODB_TABLE

logger = logging.getLogger(__name__)

def handle_delete_profile(team_tag: str, model_type: str, version: str):
    """Delete profile details from DynamoDB and Bedrock"""
    if not aws_clients.dynamodb:
        raise RuntimeError("DynamoDB client not available")

    model_type_version = f"{model_type}#{version}"

    # Use DynamoDB Table resource for easier item access
    dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
    table = dynamodb.Table(DYNAMODB_TABLE)
    
    try:
        # Get the profile first
        response = table.get_item(
            Key={
                'team_tag': team_tag,
                'model_type_version': model_type_version
            }
        )
    except ClientError as e:
        logger.error(f"Failed to get item from Bedrock profile: {e}")
        raise

    item = response.get('Item')
    if not item:
        raise ValueError(f"No profile found for team {team_tag}")
            
    profile_id = item['profile_id']
        
    # Delete from Bedrock
    try:
        aws_clients.bedrock.delete_inference_profile(
            inferenceProfileIdentifier=profile_id
        )
        logger.info(f"Deleted Bedrock inference profile: {profile_id}")
    except ClientError as e:
        logger.error(f"Failed to delete Bedrock application inference profile: {e}")
        raise

    # Delete from DynamoDB using client (for consistency with create/get)
    try:
        Key = {
            'team_tag': {'S': team_tag},
            'model_type_version': {'S': model_type_version}
        }
            
        aws_clients.dynamodb.delete_item(
            TableName=DYNAMODB_TABLE,
            Key=Key
        )
            
        logger.info(f"Deleted profile for team {team_tag}")
        return {"deleted": True}    

    except ClientError as e:
        logger.error(f"Failed to delete profile from DynamoDB table: {e}")
        raise

print(f"Successfully deleted application inference profile")
