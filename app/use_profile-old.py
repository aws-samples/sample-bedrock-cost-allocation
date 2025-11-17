#!/usr/bin/env python3
"""
Use profile functionality for AWS Bedrock Inference Profile Management API
"""

import logging
from typing import Optional
from botocore.exceptions import ClientError
from utils import aws_clients
from get_profile import handle_get_profile

logger = logging.getLogger(__name__)

def handle_use_profile(team_tag: str, model_type: str, version: str, user_message: str, system_prompt: Optional[str] = None):
    """Use a profile to have a conversation with the AI model"""
    if not aws_clients.bedrock_runtime:
        raise RuntimeError("Bedrock Runtime client not available")

    # Get the profile first
    profile = handle_get_profile(team_tag, model_type, version)
    if not profile:
        raise ValueError(f"No profile found for team {team_tag} with model {model_type}")

    if not system_prompt:
        system_prompt = "You are a personal AI assistant, try to provide most accurate answers to the user query"

    try:
        response = aws_clients.bedrock_runtime.converse(
            modelId=profile['profile_id'],
            system=[{"text": system_prompt}],
            messages=[{
                "role": "user",
                "content": [{"text": user_message}]
            }]
        )

        response_text = response["output"]['message']['content'][0]['text']
        logger.info(f"Successfully completed conversation with profile {profile['profile_id']}")
        
        return {
            "conversation_response": response_text,
            "profile_used": profile['profile_id']
        }

    except ClientError as e:
        logger.error(f"Failed to converse with model: {e}")
        raise
