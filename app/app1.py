#!/usr/bin/env python3
"""
AWS Bedrock Inference Profile Management API

A Flask application that manages AWS Bedrock inference profiles for teams,
stores metadata in DynamoDB, and provides AI conversation capabilities.
"""

import json
import logging
import os
import time
from typing import Dict, Optional, Tuple, Any

import boto3
import botocore
from flask import Flask, request, jsonify
from botocore.exceptions import ClientError

def sanitize_user_input(value: str) -> str:
    """Safe sanitization without regex - AWS model ID compatible."""
    if not isinstance(value, str):
        return "invalid"
    
    # AWS-compatible characters: model IDs use dots, hyphens, colons, underscores
    safe_chars = set('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/')
    sanitized = ''.join(c for c in value if c in safe_chars)
    
    return sanitized[:100] if sanitized else "unknown"

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# retrieve user account id using STS
def get_account_id() -> str:
    sts_client = boto3.client('sts')
    account_id = sts_client.get_caller_identity()['Account']
    return account_id
    
def load_model_config(config_path=None):
    """Load model configuration from JSON file"""
    try:
        # Use environment variable or default path
        if config_path is None:
            config_path = os.environ.get('MODEL_CONFIG_PATH', 'config/models.json')

        # Get the directory of the current script
        script_dir = os.path.dirname(os.path.abspath(__file__))
        full_config_path = os.path.join(script_dir, config_path)

        # Debug logging
        logger.info(f"Script directory: {script_dir}")
        logger.info(f"Config path: {config_path}")
        logger.info(f"Full config path: {full_config_path}")
        logger.info(f"Config file exists: {os.path.exists(full_config_path)}")

        # List directory contents for debugging
        if os.path.exists(script_dir):
            logger.info(f"Script directory contents: {os.listdir(script_dir)}")
            config_dir = os.path.join(script_dir, 'config')
            if os.path.exists(config_dir):
                logger.info(f"Config directory contents: {os.listdir(config_dir)}")

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

        logger.info(f"Configuration loaded successfully from {full_config_path}")
        logger.info(f"Loaded {len(model_registry)} models and {len(team_defaults)} team defaults")

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
    except FileNotFoundError as e:
        logger.error(f"Configuration file not found: {full_config_path}")
        logger.error(f"Current working directory: {os.getcwd()}")
        logger.error(f"Error details: {e}")

        # Try alternative paths
        alternative_paths = [
            "/app/config/models.json",
            "./config/models.json",
            "models.json",
            "/app/models.json"
        ]

        for alt_path in alternative_paths:
            if os.path.exists(alt_path):
                logger.warning(f"Found config file at alternative path: {alt_path}")
                with open(alt_path, 'r') as f:
                    config = json.load(f)
                break
        else:
            logger.error("No configuration file found in any expected location")
            raise
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in configuration file: {e}")
        raise
    except KeyError as e:
        logger.error(f"Missing required configuration key: {e}")
        raise
    except Exception as e:
        logger.error(f"Failed to load configuration: {e}")
        raise


# Load configuration from external JSON file
try:
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
except Exception as e:
    logger.error(f"Failed to load model configuration: {e}")
    logger.error("Application cannot start without valid configuration")
    raise

def sanitize_profile_name(team_tag: str, model_type: str, version: str) -> str:
    """Sanitize profile name to match AWS pattern: ([0-9a-zA-Z][ _-]?)+"""
    # Replace dots with underscores and ensure only allowed characters
    sanitized_version = version.replace('.', '_')
    profile_name = f"{team_tag}_{model_type}_{sanitized_version}"

    # Ensure the name only contains allowed characters: alphanumeric, space, underscore, hyphen
    sanitized_name = re.sub(r'[^0-9a-zA-Z _-]', '_', profile_name)

    # Ensure it doesn't end with a separator
    sanitized_name = sanitized_name.rstrip('_-')

    return sanitized_name


def get_model_arn(model_type: str, version: str, team_tag: str = None) -> str:
    """Get model ARN based on model_type and version, with team fallback."""
    # First try to get from MODEL_REGISTRY
    print(f"in get_model_arn method model_type is {model_type}")
    print(f"in get_model_arn method version is {version}")
    model_key = (model_type, version)
    print(f"in get_model_arn method model key is {model_key}")
    print(f"MODEL_REGISTRY is {MODEL_REGISTRY}")
    account_id=get_account_id()
    if model_key in MODEL_REGISTRY:
        print(f"This is true condition")
        model_id = MODEL_REGISTRY[model_key]
        print(f"in get_model_arn method model id is {model_id}")
        model_arn = f"arn:aws:bedrock:{AWS_REGION}:{account_id}:inference-profile/{model_id}"
        return model_id,model_arn
    
    
    # If not found and team_tag provided, try team default
    if team_tag and team_tag in TEAM_DEFAULT_MODELS:
        default_model_type, default_version = TEAM_DEFAULT_MODELS[team_tag]
        default_key = (default_model_type, default_version)
        if default_key in MODEL_REGISTRY:
            logger.warning(f"Model {model_type} v{version} not found, using team {team_tag} default")
            return MODEL_REGISTRY[default_key]

    raise ValueError(f"Model ARN not found for model_type: {model_type}, version: {version}")


app = Flask(__name__)


class AWSClientManager:
    """Manages AWS client initialization and provides centralized error handling."""

    def __init__(self):
        self.bedrock_runtime = None
        self.bedrock = None
        self.dynamodb = None
        self._initialize_clients()

    def _initialize_clients(self):
        """Initialize AWS clients with proper error handling."""
        try:
            self.bedrock_runtime = boto3.client('bedrock-runtime', region_name=AWS_REGION)
            logger.info("Bedrock Runtime client initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize Bedrock Runtime client: {e}")

        try:
            self.bedrock = boto3.client('bedrock', region_name=AWS_REGION)
            logger.info("Bedrock client initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize Bedrock client: {e}")

        try:
            self.dynamodb = boto3.client('dynamodb', region_name=AWS_REGION)
            logger.info("DynamoDB client initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize DynamoDB client: {e}")


class InferenceProfileManager:
    """Handles inference profile operations."""

    def __init__(self, aws_clients: AWSClientManager):
        self.aws_clients = aws_clients

    def create_profile(self, team_tag: str, model_type: str, version: str) -> Dict[str, Any]:
        """Create an inference profile for a team."""
        if not self.aws_clients.bedrock:
            raise RuntimeError("Bedrock client not available")

        model_id,model_arn = get_model_arn(model_type, version, team_tag)

        print(f"model ARN in create profile is {model_arn}")

        # Validate model availability
#        if not validate_model_availability(model_id, self.aws_clients.bedrock):
#            logger.error(f"Model {model_id} is not available in region {AWS_REGION}")
#            raise ValueError(f"Model {model_id} is not available in region {AWS_REGION}")

        tags = [{'key': 'team', 'value': team_tag}, {'key': 'model_type', 'value': model_type}, {'key': 'version', 'value': version}]

        # Create a sanitized profile name that matches AWS requirements
        profile_name = sanitize_profile_name(team_tag, model_type, version)

        try:
            response = self.aws_clients.bedrock.create_inference_profile(
                inferenceProfileName=profile_name,
                description=f"Inference profile for {team_tag} with {model_type} version {version}",
                modelSource={'copyFrom': model_arn},
                tags=tags
            )

            logger.info(f"Created inference profile '{profile_name}' for team {team_tag} with model {model_arn}")
            print(f"Created inference profile '{profile_name}' for team {team_tag} with model {model_arn}")
            return response

        except ClientError as e:
            logger.error(f"Failed to create inference profile for {team_tag}: {e}")
            raise


class ProfileDataManager:
    """Handles DynamoDB operations for profile metadata."""

    def __init__(self, aws_clients: AWSClientManager):
        self.aws_clients = aws_clients

    def store_profile(self, team_tag: str, model_type: str, version: str, profile_arn: str, model_arn: str) -> bool:
        """Store profile details in DynamoDB."""
        if not self.aws_clients.dynamodb:
            raise RuntimeError("DynamoDB client not available")

        if not all([team_tag, model_type, version, profile_arn, model_arn]):
            raise ValueError("All parameters are required")

        # Create composite sort key
        model_type_version = f"{model_type}#{version}"

        item = {
            'team_tag': {'S': team_tag},
            'model_type_version': {'S': model_type_version},
            'model_type': {'S': model_type},  # Keep as separate attribute for queries
            'version': {'S': version},        # Keep as separate attribute for queries
            'profile_id': {'S': profile_arn},
            'model_arn': {'S': model_arn}
        }

        try:
            self.aws_clients.dynamodb.put_item(
                TableName=DYNAMODB_TABLE,
                Item=item,
                ConditionExpression='attribute_not_exists(team_tag) AND attribute_not_exists(model_type_version)'
            )

            logger.info(f"Stored profile details for team {team_tag}, model_type {model_type}, version {version}")
            return True

        except ClientError as e:
            if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
                logger.warning(f"Profile already exists for team {team_tag}, model_type {model_type}, version {version}")
                raise ValueError(f"Profile already exists for team {team_tag} and model_type {model_type} and version {version}")
            else:
                logger.error(f"Failed to store profile details: {e}")
                raise

    def get_profile(self, team_tag: str, model_type: str, version: str) -> Optional[Dict[str, str]]:
        """Retrieve profile details from DynamoDB."""
        if not self.aws_clients.dynamodb:
            raise RuntimeError("DynamoDB client not available")

        # Create composite sort key
        model_type_version = f"{model_type}#{version}"

        try:
            response = self.aws_clients.dynamodb.get_item(
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

            logger.info(f"Retrieved profile for team {team_tag}, model_type {model_type}, version {version}")
            return profile

        except ClientError as e:
            logger.error(f"Failed to retrieve profile: {e}")
            raise
    '''
    def delete_profile(self, team_tag: str, model_type: str, version: str) -> bool:
        """Delete profile details from DynamoDB."""
        if not self.aws_clients.dynamodb:
            raise RuntimeError("DynamoDB client not available")

        # Create composite sort key
        model_type_version = f"{model_type}#{version}"

        Key={
                    'team_tag': {'S': team_tag},
                    'model_type_version': {'S': model_type_version}
            }
        
        print("key is {key}")
        
        try:
            response = self.aws_clients.dynamodb.DYNAMODB_TABLE.get_item(Key=Key)
            item = response.get('Item')
        except ClientError as e:
            logger.error(f"Failed to get item from DynamoDB table: {e}")
            raise 

        print(f"response from get item call is {response}")  
        
        try:
            # Fallback to general inference profile deletion
            self.aws_clients.bedrock.delete_inference_profile(
                inferenceProfileIdentifier=item['profile_id']
            )

        except ClientError as e:
            logger.error(f"Failed to delete application inference profile: {e}")
            raise

        try:
            self.aws_clients.dynamodb.delete_item(
                TableName=DYNAMODB_TABLE,    
                )
        except ClientError as e:
            logger.error(f"Failed to delete profile from DynamoDB: {e}")
            raise
    
        logger.info(f"Deleted profile for team {team_tag}, model_type {model_type}, version {version}")
    '''

    def delete_profile(self, team_tag: str, model_type: str, version: str) -> bool:
        """Delete profile details from DynamoDB."""
        if not self.aws_clients.dynamodb:
            raise RuntimeError("DynamoDB client not available")

        # Create composite sort key
        model_type_version = f"{model_type}#{version}"

        Key={
                    'team_tag': {'S': team_tag},
                    'model_type_version': {'S': model_type_version}
            }
        
        print(f"key is {Key}")
        
        # Use DynamoDB Table resource
        dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
        table = dynamodb.Table(DYNAMODB_TABLE)
        
        try:
            response = table.get_item(
                Key={
                    'team_tag': team_tag,
                    'model_type_version': model_type_version
                }
            )
            item = response.get('Item')
            if not item:
                raise ValueError(f"No profile found for team {team_tag}")
        except ClientError as e:
            logger.error(f"Failed to get item from DynamoDB table: {e}")
            raise 

        print(f"response from get item call is {response}")  
        
        try:
            # Fallback to general inference profile deletion
            self.aws_clients.bedrock.delete_inference_profile(
                inferenceProfileIdentifier=item['profile_id']
            )

        except ClientError as e:
            logger.error(f"Failed to delete application inference profile: {e}")
            raise

        try:
            self.aws_clients.dynamodb.delete_item(
                TableName=DYNAMODB_TABLE,
                Key=Key
            )
        except ClientError as e:
            logger.error(f"Failed to delete profile from DynamoDB: {e}")
            raise
    
        logger.info(f"Deleted profile for team {team_tag}, model_type {model_type}, version {version}")

class ConversationManager:
    """Handles AI conversations using Bedrock models."""

    def __init__(self, aws_clients: AWSClientManager):
        self.aws_clients = aws_clients

    def converse_with_model(self, profile_id: str, user_message: str, system_prompt: Optional[str] = None) -> str:
        """Have a conversation with the AI model using the specified profile."""
        if not self.aws_clients.bedrock_runtime:
            raise RuntimeError("Bedrock Runtime client not available")

        if not system_prompt:
            system_prompt = "You are a personal AI assistant, try to provide most accurate answers to the user query"

        try:
            response = self.aws_clients.bedrock_runtime.converse(
                modelId=profile_id,
                system=[{"text": system_prompt}],
                messages=[{
                    "role": "user",
                    "content": [{"text": user_message}]
                }]
            )

            response_text = response["output"]['message']['content'][0]['text']
            logger.info(f"Successfully completed conversation with profile {profile_id}")
            return response_text

        except ClientError as e:
            logger.error(f"Failed to converse with model: {e}")
            raise


# Initialize managers
aws_clients = AWSClientManager()
profile_manager = InferenceProfileManager(aws_clients)
data_manager = ProfileDataManager(aws_clients)
conversation_manager = ConversationManager(aws_clients)


def validate_request_data(data: Dict[str, Any]) -> Tuple[str, str, str, str, Optional[str]]:
    """Validate and extract request parameters."""
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

    # Validate user_message is provided for 'use' action
    if action == 'use' and not user_message:
        raise ValueError("user_message is required for 'use' action")
    
    print(f"method action is {action}")
    print(f"method model type is {model_type}")
    print(f"method version is {version}")
    print(f"method team tag is {team_tag}")

    return team_tag, action, model_type, version, user_message
    


def create_success_response(data: Any, processing_time: float) -> Tuple[Dict[str, Any], int]:
    """Create a standardized success response."""
    return {
        "status": "success",
        "data": data,
        "processing_time": round(processing_time, 3)
    }, 200


def create_error_response(message: str, status_code: int = 500) -> Tuple[Dict[str, Any], int]:
    """Create a standardized error response."""
    return {
        "status": "error",
        "message": message
    }, status_code


@app.route('/team-profile', methods=['POST'])
def handle_team_profile():
    """Main endpoint for team profile operations."""
    start_time = time.time()

    try:
        # Get JSON data with better error handling
        try:
            data = request.get_json()
            if data is None:
                return create_error_response("No JSON data provided or invalid JSON format", 400)
        except Exception as e:
            logger.error(f"JSON parsing error: {e}")
            return create_error_response("Failed to parse JSON data", 400)

        team_tag, action, model_type, version, user_message = validate_request_data(data)

        print(f"action is {action}")
        print(f"model type is {model_type}")
        print(f"version is {version}")
        print(f"team tag is {team_tag}")


        if action == 'create':
            # Create inference profile
            print("starting to create the profile")
            profile_response = profile_manager.create_profile(team_tag, model_type, version)
            print(f"profile response is {profile_response}")
            profile_arn = profile_response['inferenceProfileArn']
            model_id,model_arn = get_model_arn(model_type, version, team_tag)

            print(f"model id in create action is {model_id}")

            # Store in DynamoDB
            data_manager.store_profile(team_tag, model_type, version, profile_arn, model_id)

            return create_success_response(profile_response, time.time() - start_time)

        elif action == 'get':
            profile = data_manager.get_profile(team_tag, model_type, version)
            if not profile:
                return create_error_response(f"No profile found for team {sanitize_user_input(team_tag)} with model {sanitize_user_input(model_type)}", 404)

            return create_success_response(profile, time.time() - start_time)

        elif action == 'delete':
            data_manager.delete_profile(team_tag, model_type, version)
            return create_success_response({"deleted": True}, time.time() - start_time)

        elif action == 'use':
            profile = data_manager.get_profile(team_tag, model_type, version)
            if not profile:
                return create_error_response(f"No profile found for team {sanitize_user_input(team_tag)} with model {sanitize_user_input(model_type)}", 404)

            # Get optional system_prompt from request data
            system_prompt = data.get('system_prompt')
            response_text = conversation_manager.converse_with_model(profile['profile_id'], user_message, system_prompt)
            return create_success_response({"conversation_response": response_text}, time.time() - start_time)

    except ValueError as e:
        logger.warning(f"Validation error: {e}")
        return create_error_response("Invalid request data", 400)


@app.route('/hello', methods=['GET'])
def hello():
    """Simple health check endpoint."""
    return create_success_response({"message": "Hello! Welcome to the API"}, 0)


@app.route('/bedrock-health', methods=['GET'])
def bedrock_health():
    """Check Bedrock service health and list available models."""
    start_time = time.time()

    try:
        if not aws_clients.bedrock:
            return create_error_response("Bedrock client not initialized")

        response = aws_clients.bedrock.list_foundation_models()

        models = [
            {
                'modelId': model['modelId'],
                'provider': model['providerName'],
                'name': model.get('modelName', 'N/A'),
                'status': model.get('modelLifecycle', {}).get('status', 'N/A')
            }
            for model in response['modelSummaries']
        ]

        # Filter Claude models for easier debugging
        claude_models = [model for model in models if 'claude' in model['modelId'].lower()]

        return create_success_response({
            "message": "Bedrock service is healthy",
            "region": AWS_REGION,
            "total_models": len(models),
            "claude_models": claude_models,
            "configured_models": dict(MODEL_REGISTRY)
        }, time.time() - start_time)

    except Exception as e:
        logger.error(f"Bedrock health check failed: {e}")
        return create_error_response("Bedrock health check failed")


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors without exposing stack traces."""
    logger.error(f"Internal server error: {error}")
    return create_error_response("Internal server error", 500)

@app.errorhandler(Exception)
def handle_exception(e):
    """Handle all unhandled exceptions without exposing stack traces."""
    logger.error(f"Unhandled exception: {e}")
    return create_error_response("An unexpected error occurred", 500)

@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors."""
    return create_error_response("Endpoint not found", 404)


if __name__ == '__main__':
    logger.info("Starting Bedrock Inference Profile Management API")
    # Use port 8080 for non-root user, fallback to 80 if PORT env var is set
    port = int(os.environ.get('PORT', 80))
    debug_mode = os.environ.get('FLASK_ENV', 'production') == 'development'

    logger.info(f"Starting Flask app on port {port}")
    app.run(host='0.0.0.0', port=port, debug=debug_mode)
