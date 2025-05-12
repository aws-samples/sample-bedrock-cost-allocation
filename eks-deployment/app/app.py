from flask import Flask, request, jsonify
import boto3
import botocore
import os
import json
import sys
from botocore.exceptions import ClientError
import time

app = Flask(__name__)

try:
    bedrock = boto3.client(
        service_name='bedrock-runtime',
        region_name='us-west-2'  # Replace with your desired region
    )
except Exception as e:
    print(f"Error initializing Bedrock client: {str(e)}")
    bedrock = None

try:
    bedrock1 = boto3.client(
        service_name='bedrock',
        region_name='us-west-2'  # Replace with your desired region
    )

except Exception as e:
    print(f"Error initializing Bedrock client: {str(e)}")
    bedrock = None


def create_inference_profile(profile_name, model_arn, tags):
    """Create Inference Profile using base model ARN"""
    response = bedrock1.create_inference_profile(
        inferenceProfileName=profile_name,
        description="test",
        modelSource={'copyFrom': model_arn},
        tags=tags
    )
    print("CreateInferenceProfile Response:", response['ResponseMetadata']['HTTPStatusCode']),
    print(f"{response}\n")
    return response

def store_profile_details(team_tag, version, profile_arn, base_model_arn):
    """
    Store inference profile details in DynamoDB

    Args:
        team_name (str): Name of the team
        profile_arn (str): ARN of the inference profile
        profile_name (str): Name of the profile
        base_model_arn (str): ARN of the base model

    Returns:
        bool: True if successful, False otherwise

    Raises:
        ValueError: If required parameters are missing or invalid
    """
    # Input validation
    if not all([team_tag, version, profile_arn, base_model_arn]):
        raise ValueError("All parameters are required")

    try:
        dynamodb = boto3.client('dynamodb', region_name='us-west-2')

        # Prepare item with required attributes
        item = {
            'team_tag': {'S': team_tag},            # Partition key
            'version': {'S': '1.0'},                # Version attribute
            'profile_id': {'S': profile_arn},         # Sort key
            'model_arn': {'S': base_model_arn}
        }

        response = dynamodb.put_item(
            TableName='team-profile',
            Item=item,
            # Add condition to prevent overwriting existing item unintentionally
            ConditionExpression='attribute_not_exists(team_tag) AND attribute_not_exists(version)'
        )

        print(f"Profile details stored in DynamoDB for profile: {team_tag}")
        return True

    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            print(f"Profile already exists for team {team_tag} with profile ID {version}")
        else:
            print(f"Profile already exists for team {team_tag} with profile ID {version}")
        raise  # Re-raise the exception for proper error handling

    except Exception as e:
        print(f"Unexpected error storing profile details: {str(e)}")
        raise

def get_specific_team_profile(team_tag,version):
    """
    Retrieve a specific profile for a team from DynamoDB

    Args:
        team_name (str): Name of the team
        profile_id (str): Profile ID to retrieve

    Returns:
        dict: Profile details if found, None otherwise
    """
    try:
        dynamodb = boto3.client('dynamodb', region_name='us-west-2')

        # Get specific item
        response = dynamodb.get_item(
            TableName='team-profile',
            Key={
                'team_tag': {'S': team_tag},
                'version': {'S': version}
            }
        )

        item = response.get('Item')
        if not item:
            print(f"No profile found for team {team_tag}")
            return None

        return {
            'team_tag': item['team_tag']['S'],
            'version' : item['version']['S'],
            'profile_id': item['profile_id']['S'],
            'model_arn': item.get('model_arn', {}).get('S', ''),
        }

    except ClientError as e:
        print(f"Error querying DynamoDB: {str(e)}")
        raise
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        raise

def delete_specific_team_profile(team_tag,version):
    """
    Delete a specific profile for a team from DynamoDB

    Args:
        team_tag (str): Name of the team
        version (str): Profile ID to delete

    Returns:
        bool: True if successful, False otherwise
    """
    try:
        dynamodb = boto3.client('dynamodb', region_name='us-west-2')

        # Delete specific item
        response = dynamodb.delete_item(
            TableName='team-profile',
            Key={
                'team_tag': {'S': team_tag},
                'version': {'S': version}
            }
        )

        print(f"Profile deleted for team {team_tag}")
        return True

    except ClientError as e:
        print(f"Error deleting profile from DynamoDB: {str(e)}")
        raise
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        raise

def create_profile(team_tag, data):
        try:
            start = time.time()
            print("Testing CreateInferenceProfile...")
            tags = [{'key': 'team', 'value': team_tag}]
            if team_tag == 'teama':
                base_model_arn = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
            if team_tag == 'teamb':
                base_model_arn = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
            response_text = create_inference_profile(team_tag, base_model_arn, tags)

            if response_text:
                try:
                    profile_arn = response_text['inferenceProfileArn']
                    success = store_profile_details(
                        team_tag=team_tag,
                        version="1.0",
                        profile_arn=profile_arn,
                        base_model_arn=base_model_arn
                    )
                    if not success:
                        print("Failed to store profile details")
                        return jsonify({
                            "error": "Failed to store profile details"
                        }), 500
                except Exception as e:
                    print(f"Profile already exists for team {team_tag}")
                    return jsonify({
                        "error":f"Profile already exists for team {team_tag}"
                    }), 500

            # Return the response
            return jsonify({
                "response": response_text,
                "processing_time": time.time() - start
            }), 200

        except botocore.exceptions.ClientError as e:
            return jsonify({
                "error": str(e)
            }), 500
        except Exception as e:
            return jsonify({
                "error": f"Unexpected error: {str(e)}"
            }), 500

def delete_profile(team_tag, version):
    start = time.time()
    try:
        response_text = delete_specific_team_profile(team_tag,version)

        # Return the response
        return jsonify({
            "response": response_text,
            "processing_time": time.time() - start
        }), 200
    except botocore.exceptions.ClientError as e:
            return jsonify({
                "details": str(e)
            }), 500

def get_profile(team_tag, version):
    start = time.time()
    try:
        response_text = get_specific_team_profile(team_tag, version)

        # Return the response
        return jsonify({
            "response": response_text,
            "processing_time": time.time() - start
        }), 200
    except botocore.exceptions.ClientError as e:
            return jsonify({
                "details": str(e)
            }), 500
    except Exception as e:
            return jsonify({
                "error": "No profile found for the team"
            }), 404

def use_profile(team_tag, version):
    start = time.time()
    try:
        profile = get_specific_team_profile(team_tag, version)

        if not profile:
            return jsonify({
                "error": f"Profile doesn't exist for team '{team_tag}' with version '{version}'"
            }), 404

        system_prompt = "You are an expert on AWS services and always provide correct and concise answers."
        input_message = "Should I be storing documents in Amazon S3 or EFS for cost effective applications?"
        start = time.time()
        response = bedrock.converse(
            modelId=profile['profile_id'],
            system=[{"text": system_prompt}],
            messages=[{
                "role": "user",
                "content": [{"text": input_message}]
            }]
        )
        # Extract the text response
        response_text = response["output"]['message']['content'][0]['text']

        # Return the response
        return jsonify({
            "response": response_text,
            "processing_time": time.time() - start
        }), 200
    except botocore.exceptions.ClientError as e:
            return jsonify({
                "details": "No profile found for the team"
            }), 500
    except Exception as e:
            return jsonify({
                "error": "No profile found for the team"
            }), 500

@app.route('/team-profile', methods=['POST'])
def handle_team_profile():
    try:
        # Get JSON data from request
        data = request.get_json()

        # Validate required parameters
        if not data:
            return jsonify({
                "error": "No data provided"
            }), 400

        team_tag = data.get('team_tag')
        action = data.get('action')

        # Validate team_tag
        if not team_tag or team_tag not in ['teama', 'teamb']:
            return jsonify({
                "error": "Invalid or missing team_tag. Must be 'teama' or 'teamb'"
            }), 400

        # Validate action
        valid_actions = ['create', 'delete', 'get', 'use']
        if not action or action not in valid_actions:
            return jsonify({
                "error": f"Invalid or missing action. Must be one of: {', '.join(valid_actions)}"
            }), 400

        # Get version from request data or use default
        version = data.get('version', '1.0')

                # Handle different actions
        if action == 'create':
            return create_profile(team_tag, data)
        elif action == 'delete':
            return delete_profile(team_tag, version)
        elif action == 'get':
            return get_profile(team_tag, version)
        elif action == 'use':
            return use_profile(team_tag, version)

    except Exception as e:
        return jsonify({
            "error": f"Unexpected error: {str(e)}"
        }), 500

# Define route for /hello
@app.route('/hello', methods=['GET'])
def hello():
    return jsonify({
        "message": "Hello! Welcome to the API",
        "status": "success"
    }), 200

# Define route for /bedrock-health
@app.route('/bedrock-health', methods=['GET'])
def bedrock_health():
    try:
        # If Bedrock client wasn't initialized successfully
        if bedrock is None:
            return jsonify({
                "message": "Bedrock client not initialized",
                "status": "error"
            }), 500

        # Create a Bedrock client for model listing (requires different client)
        bedrock_model_client = boto3.client('bedrock', region_name='us-west-2')

        # Get list of available models
        response = bedrock_model_client.list_foundation_models()

        # Extract model information
        models = []
        for model in response['modelSummaries']:
            models.append({
                'modelId': model['modelId'],
                'provider': model['providerName'],
                'name': model.get('modelName', 'N/A')
            })

        return jsonify({
            "message": "Bedrock models retrieved successfully",
            "status": "success",
            "models": models
        }), 200

    except botocore.exceptions.ClientError as e:
        return jsonify({
            "message": f"AWS API error: {str(e)}",
            "status": "error"
        }), 500
    except Exception as e:
        return jsonify({
            "message": f"Error: {str(e)}",
            "status": "error"
        }), 500

# Error handler for 404 Not Found
@app.errorhandler(404)
def not_found(error):
    return jsonify({
        "message": "Endpoint not found",
        "status": "error"
    }), 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=True)
