#!/usr/bin/env python3
"""
Common utilities and classes for AWS Bedrock Inference Profile Management API
"""

import json
import logging
import os
import re
from typing import Dict, Optional, Tuple, Any

import boto3
import botocore
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def get_account_id() -> str:
    """Retrieve user account id using STS"""
    sts_client = boto3.client('sts')
    account_id = sts_client.get_caller_identity()['Account']
    return account_id
    
def load_model_config(config_path=None):
    """Load model configuration from JSON file"""
    try:
        if config_path is None:
            config_path = os.environ.get('MODEL_CONFIG_PATH', 'config/models.json')

        script_dir = os.path.dirname(os.path.abspath(__file__))
        full_config_path = os.path.join(script_dir, config_path)

        logger.info(f"Loading config from: {full_config_path}")

        with open(full_config_path, 'r') as f:
            config = json.load(f)

        # Convert model_registry keys back to tuples
        model_registry = {}
        for key, value in config['model_registry'].items():
            model_type, version = key.split('_', 1)
            model_registry[(model_type, version)] = value

        # Build team defaults as tuples
        team_defaults = {}
        for team, data in config['team_defaults'].items():
            team_defaults[team] = (data['model_type'], data['version'])

        logger.info(f"Configuration loaded successfully")

        return {
            'MODEL_REGISTRY': model_registry,
            'TEAM_DEFAULT_MODELS': team_defaults,
            'VALID_TEAMS': config['validation']['valid_teams'],
            'VALID_MODEL_TYPES': config['validation']['valid_model_types'],
            'VALID_VERSIONS': config['validation']['valid_versions'],
            'VALID_ACTIONS': config['validation']['valid_actions'],
            'DEFAULT_VERSION': config['validation']['default_version'],
            'AWS_REGION': config['aws_config']['region'],
            'DYNAMODB_TABLE': config['aws_config']['dynamodb_table']
        }
    except Exception as e:
        logger.error(f"Failed to load configuration: {e}")
        raise

# Load configuration
config = load_model_config()
MODEL_REGISTRY = config['MODEL_REGISTRY']
TEAM_DEFAULT_MODELS = config['TEAM_DEFAULT_MODELS']
VALID_TEAMS = config['VALID_TEAMS']
VALID_MODEL_TYPES = config['VALID_MODEL_TYPES']
VALID_VERSIONS = config['VALID_VERSIONS']
VALID_ACTIONS = config['VALID_ACTIONS']
DEFAULT_VERSION = config['DEFAULT_VERSION']
AWS_REGION = config['AWS_REGION']
DYNAMODB_TABLE = config['DYNAMODB_TABLE']

def sanitize_profile_name(team_tag: str, model_type: str, version: str) -> str:
    """Sanitize profile name to match AWS pattern"""
    sanitized_version = version.replace('.', '_')
    profile_name = f"{team_tag}_{model_type}_{sanitized_version}"
    sanitized_name = re.sub(r'[^0-9a-zA-Z _-]', '_', profile_name)
    sanitized_name = sanitized_name.rstrip('_-')
    return sanitized_name

def get_model_arn(model_type: str, version: str, team_tag: str = None) -> Tuple[str, str]:
    """Get model ARN based on model_type and version"""
    model_key = (model_type, version)
    account_id = get_account_id()
    
    if model_key in MODEL_REGISTRY:
        model_id = MODEL_REGISTRY[model_key]
        model_arn = f"arn:aws:bedrock:{AWS_REGION}:{account_id}:inference-profile/{model_id}"
        return model_id, model_arn
    
    if team_tag and team_tag in TEAM_DEFAULT_MODELS:
        default_model_type, default_version = TEAM_DEFAULT_MODELS[team_tag]
        default_key = (default_model_type, default_version)
        if default_key in MODEL_REGISTRY:
            logger.warning(f"Model {model_type} v{version} not found, using team {team_tag} default")
            model_id = MODEL_REGISTRY[default_key]
            model_arn = f"arn:aws:bedrock:{AWS_REGION}:{account_id}:inference-profile/{model_id}"
            return model_id, model_arn

    raise ValueError(f"Model ARN not found for model_type: {model_type}, version: {version}")

class AWSClientManager:
    """Manages AWS client initialization"""

    def __init__(self):
        self.bedrock_runtime = None
        self.bedrock = None
        self.dynamodb = None
        self._initialize_clients()

    def _initialize_clients(self):
        """Initialize AWS clients"""
        try:
            self.bedrock_runtime = boto3.client('bedrock-runtime', region_name=AWS_REGION)
            self.bedrock = boto3.client('bedrock', region_name=AWS_REGION)
            self.dynamodb = boto3.client('dynamodb', region_name=AWS_REGION)
            logger.info("AWS clients initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize AWS clients: {e}")

def validate_request_data(data: Dict[str, Any]) -> Tuple[str, str, str, str, Optional[str]]:
    """Validate and extract request parameters"""
    if not data:
        raise ValueError("No data provided")

    team_tag = data.get('team_tag')
    if not team_tag or team_tag not in VALID_TEAMS:
        raise ValueError(f"Invalid team_tag. Must be one of: {', '.join(VALID_TEAMS)}")

    action = data.get('action')
    if not action or action not in VALID_ACTIONS:
        raise ValueError(f"Invalid action. Must be one of: {', '.join(VALID_ACTIONS)}")

    model_type = data.get('model_type')
    if not model_type:
        raise ValueError("model_type is required")

    version = data.get('version', DEFAULT_VERSION)
    user_message = data.get('user_message')

    if action == 'use' and not user_message:
        raise ValueError("user_message is required for 'use' action")

    return team_tag, action, model_type, version, user_message

def create_success_response(data: Any, processing_time: float) -> Tuple[Dict[str, Any], int]:
    """Create a standardized success response"""
    return {
        "status": "success",
        "data": data,
        "processing_time": round(processing_time, 3)
    }, 200

def create_error_response(message: str, status_code: int = 500) -> Tuple[Dict[str, Any], int]:
    """Create a standardized error response"""
    return {
        "status": "error",
        "message": message
    }, status_code

# Initialize AWS clients
aws_clients = AWSClientManager()
