#!/usr/bin/env python3
"""
Get profile functionality for AWS Bedrock Inference Profile Management API
"""

import logging
from typing import Optional, Dict
from botocore.exceptions import ClientError
from utils import aws_clients, DYNAMODB_TABLE

logger = logging.getLogger(__name__)

def handle_get_profile(team_tag: str, model_type: str, version: str) -> Optional[Dict[str, str]]:
    """Retrieve profile details from DynamoDB"""
    if not aws_clients.dynamodb:
        raise RuntimeError("DynamoDB client not available")

    model_type_version = f"{model_type}#{version}"

    try:
        response = aws_clients.dynamodb.get_item(
            TableName=DYNAMODB_TABLE,
            Key={
                'team_tag': {'S': team_tag},
                'model_type_version': {'S': model_type_version}
            }
        )

        item = response.get('Item')
        if not item:
            logger.info(f"No profile found for team {team_tag}, model_type {model_type}, version {version}")
            return None

        profile = {
            'team_tag': item['team_tag']['S'],
            'model_type': item['model_type']['S'],
            'version': item['version']['S'],
            'profile_id': item['profile_id']['S'],
            'model_arn': item.get('model_arn', {}).get('S', '')
        }

        logger.info(f"Retrieved profile for team {team_tag}")
        return profile

    except ClientError as e:
        logger.error(f"Failed to retrieve profile: {e}")
        raise
