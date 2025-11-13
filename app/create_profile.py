#!/usr/bin/env python3
"""
Create profile functionality for AWS Bedrock Inference Profile Management API
"""

import logging
from botocore.exceptions import ClientError
from utils import (
    aws_clients, get_model_arn, sanitize_profile_name, 
    AWS_REGION, DYNAMODB_TABLE
)

logger = logging.getLogger(__name__)

def handle_create_profile(team_tag: str, model_type: str, version: str):
    """Create an inference profile for a team"""
    if not aws_clients.bedrock:
        raise RuntimeError("Bedrock client not available")

    model_id, model_arn = get_model_arn(model_type, version, team_tag)
    
    tags = [
        {'key': 'Team', 'value': team_tag}, 
        {'key': 'model_type', 'value': model_type}, 
        {'key': 'version', 'value': version}
    ]

    profile_name = sanitize_profile_name(team_tag, model_type, version)

    try:
        # Create inference profile
        response = aws_clients.bedrock.create_inference_profile(
            inferenceProfileName=profile_name,
            description=f"Inference profile for {team_tag} with {model_type} version {version}",
            modelSource={'copyFrom': model_arn},
            tags=tags
        )

        profile_arn = response['inferenceProfileArn']
        
        # Store in DynamoDB
        store_profile_in_dynamodb(team_tag, model_type, version, profile_arn, model_id)
        
        logger.info(f"Created inference profile '{profile_name}' for team {team_tag}")
        return response

    except ClientError as e:
        logger.error(f"Failed to create inference profile for {team_tag}: {e}")
        raise

def store_profile_in_dynamodb(team_tag: str, model_type: str, version: str, profile_arn: str, model_arn: str):
    """Store profile details in DynamoDB"""
    if not aws_clients.dynamodb:
        raise RuntimeError("DynamoDB client not available")

    model_type_version = f"{model_type}#{version}"

    item = {
        'team_tag': {'S': team_tag},
        'model_type_version': {'S': model_type_version},
        'model_type': {'S': model_type},
        'version': {'S': version},
        'profile_id': {'S': profile_arn},
        'model_arn': {'S': model_arn}
    }

    try:
        aws_clients.dynamodb.put_item(
            TableName=DYNAMODB_TABLE,
            Item=item,
            ConditionExpression='attribute_not_exists(team_tag) AND attribute_not_exists(model_type_version)'
        )
        logger.info(f"Stored profile details for team {team_tag}")
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            raise ValueError(f"Profile already exists for team {team_tag}")
        else:
            logger.error(f"Failed to store profile details: {e}")
            raise
