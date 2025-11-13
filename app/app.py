#!/usr/bin/env python3
"""
Main Flask application for AWS Bedrock Inference Profile Management API
"""

import logging
import os
import time
import json
from flask import Flask, request

from utils import (
    validate_request_data, create_success_response, create_error_response,
    aws_clients, AWS_REGION, MODEL_REGISTRY
)
from create_profile import handle_create_profile
from get_profile import handle_get_profile
from delete_profile import handle_delete_profile
from use_profile import handle_use_profile

logger = logging.getLogger(__name__)

app = Flask(__name__)

@app.route('/team-profile', methods=['POST'])
def handle_team_profile():
    """Main endpoint for team profile operations"""
    start_time = time.time()

    try:
        # Get JSON data
        try:
            data = request.get_json()
            if data is None:
                return create_error_response("No JSON data provided or invalid JSON format", 400)
        except Exception as e:
            logger.error(f"JSON parsing error: {e}")
            return create_error_response(f"Failed to parse JSON: {str(e)}", 400)

        # Validate request data
        team_tag, action, model_type, version, user_message = validate_request_data(data)

        # Route to appropriate handler
        if action == 'create':
            output = handle_create_profile(team_tag, model_type, version)
            #out1={"inferenceprofilearn":output["inferenceProfileArn"]}
            print(output)
            #result=json.loads(output)
            result=output["inferenceProfileArn"]

        elif action == 'get':
            result = handle_get_profile(team_tag, model_type, version)
            if not result:
                return create_error_response(f"No profile found for team {team_tag}", 404)
        elif action == 'delete':
            result = handle_delete_profile(team_tag, model_type, version)
        elif action == 'use':
            system_prompt = data.get('system_prompt')
            result = handle_use_profile(team_tag, model_type, version, user_message, system_prompt)

        return create_success_response(result, time.time() - start_time)

    except ValueError as e:
        logger.warning(f"Validation error: {e}")
        return create_error_response(str(e), 400)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return create_error_response(str(e), 500)

@app.route('/hello', methods=['GET'])
def hello():
    """Simple health check endpoint"""
    return create_success_response({"message": "Hello! Welcome to the API"}, 0)

@app.route('/bedrock-health', methods=['GET'])
def bedrock_health():
    """Check Bedrock service health and list available models"""
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

        claude_models = [model for model in models if 'claude' in model['modelId'].lower()]

        # Convert tuple keys to strings for JSON serialization
        configured_models = {f"{k[0]}_{k[1]}": v for k, v in MODEL_REGISTRY.items()}

        return create_success_response({
            "message": "Bedrock service is healthy",
            "region": AWS_REGION,
            "total_models": len(models),
            "claude_models": claude_models,
            "configured_models": configured_models
        }, time.time() - start_time)

    except Exception as e:
        logger.error(f"Bedrock health check failed: {e}")
        return create_error_response(f"Bedrock health check failed: {str(e)}")

@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors"""
    return create_error_response("Endpoint not found", 404)

@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    logger.error(f"Internal server error: {error}")
    return create_error_response("Internal server error", 500)

if __name__ == '__main__':
    logger.info("Starting Bedrock Inference Profile Management API")
    port = int(os.environ.get('PORT', 80))
    debug_mode = os.environ.get('FLASK_ENV', 'production') == 'development'

    logger.info(f"Starting Flask app on port {port}")
    app.run(host='0.0.0.0', port=port, debug=debug_mode)
