#############################################################################
# Script Name: team-profile-client.sh
# Description: This script is consumer script for nova-pro model for the application deployed on EKS cluster for application inference profile.
#
# Author: Omkar Deshmane
# Date: November 2025
#
# Usage: ./scripts/[script_name.sh]
#
#############################################################################
#!/bin/bash

# Define valid actions and team tags
valid_actions=("create" "delete" "get" "use")
valid_teams=("teama" "teamb")
valid_model_types=("nova-pro")
valid_versions=("1.0")

# Function to validate action
validate_action() {
    local input_action=$1
    for valid_action in "${valid_actions[@]}"; do
        if [ "$input_action" == "$valid_action" ]; then
            return 0  # Valid action found
        fi
    done
    return 1  # Invalid action
}

# Function to validate team tag
validate_team() {
    local input_team=$1
    for valid_team in "${valid_teams[@]}"; do
        if [ "$input_team" == "$valid_team" ]; then
            return 0  # Valid team found
        fi
    done
    return 1  # Invalid team
}

# Function to validate model type
validate_model_type() {
    local input_model_type=$1
    for valid_model_type in "${valid_model_types[@]}"; do
        if [ "$input_model_type" == "$valid_model_type" ]; then
            return 0  # Valid model type found
        fi
    done
    return 1  # Invalid model type
}

# Function to validate version
validate_version() {
    local input_version=$1
    for valid_version in "${valid_versions[@]}"; do
        if [ "$input_version" == "$valid_version" ]; then
            return 0  # Valid version found
        fi
    done
    return 1  # Invalid version
}

# Clear screen
clear

echo "Welcome to Team Profile API Client"
echo "================================="

# Display available options
echo "Available actions:"
echo "-----------------"
for action in "${valid_actions[@]}"; do
    echo "- $action"
done

echo -e "\nAvailable model types:"
echo "---------------------"
for model_type in "${valid_model_types[@]}"; do
    echo "- $model_type"
done

echo -e "\nAvailable versions:"
echo "------------------"
for version in "${valid_versions[@]}"; do
    echo "- $version"
done

echo -e "\nAvailable teams:"
echo "---------------"
for team in "${valid_teams[@]}"; do
    echo "- $team"
done
echo

# Get and validate action
while true; do
    read -p "Enter action: " action
    if validate_action "$action"; then
        break
    else
        echo "Error: Invalid action. Please choose from: ${valid_actions[*]}"
    fi
done

# Get and validate team tag
echo -e "\nValid teams: ${valid_teams[*]}"
while true; do
    read -p "Enter team tag: " team_tag
    if validate_team "$team_tag"; then
        break
    else
        echo "Error: Invalid team tag. Please choose from: ${valid_teams[*]}"
    fi
done

# Get and validate model type
echo -e "\nValid model types: ${valid_model_types[*]}"
while true; do
    read -p "Enter model type: " model_type
    if validate_model_type "$model_type"; then
        break
    else
        echo "Error: Invalid model type. Please choose from: ${valid_model_types[*]}"
    fi
done

# Get and validate version (with default)
echo -e "\nValid versions: ${valid_versions[*]}"
read -p "Enter version (default: 1.0): " version
if [ -z "$version" ]; then
    version="1.0"
elif ! validate_version "$version"; then
    echo "Error: Invalid version. Only allowed version is 1.0"
    exit 1
fi

# Get user message if action is 'use'
if [ "$action" == "use" ]; then
    echo -e "\nFor 'use' action, a user message is required."
    read -p "Enter your message: " user_message
    while [ -z "$user_message" ]; do
        echo "Error: User message cannot be empty for 'use' action."
        read -p "Enter your message: " user_message
    done
fi

# Make the API call with conditional parameters
service_url=$(kubectl get svc inferencepoc-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
#service_url="127.0.0.1:80"
echo -e "\nService url is $service_url"
echo -e "\nMaking API call..."

# Function to create JSON payload safely
create_json_payload() {
    local team_tag="$1"
    local action="$2"
    local model_type="$3"
    local version="$4"
    local user_message="$5"

    # Use Python to create proper JSON (most reliable method)
    if command -v python3 &> /dev/null; then
        if [ -n "$user_message" ]; then
            python3 -c "
import json
import sys
data = {
    'team_tag': sys.argv[1],
    'action': sys.argv[2],
    'model_type': sys.argv[3],
    'version': sys.argv[4],
    'user_message': sys.argv[5]
}
print(json.dumps(data, indent=2))
" "$team_tag" "$action" "$model_type" "$version" "$user_message"
        else
            python3 -c "
import json
import sys
data = {
    'team_tag': sys.argv[1],
    'action': sys.argv[2],
    'model_type': sys.argv[3],
    'version': sys.argv[4]
}
print(json.dumps(data, indent=2))
" "$team_tag" "$action" "$model_type" "$version"
        fi
    # Fallback to jq if available
    elif command -v jq &> /dev/null; then
        if [ -n "$user_message" ]; then
            jq -n \
                --arg team_tag "$team_tag" \
                --arg action "$action" \
                --arg model_type "$model_type" \
                --arg version "$version" \
                --arg user_message "$user_message" \
                '{team_tag: $team_tag, action: $action, model_type: $model_type, version: $version, user_message: $user_message}'
        else
            jq -n \
                --arg team_tag "$team_tag" \
                --arg action "$action" \
                --arg model_type "$model_type" \
                --arg version "$version" \
                '{team_tag: $team_tag, action: $action, model_type: $model_type, version: $version}'
        fi
    else
        # Basic fallback with simple escaping (not recommended for production)
        echo "Warning: Neither python3 nor jq found. Using basic JSON generation." >&2
        if [ -n "$user_message" ]; then
            # Simple escape for basic cases
            escaped_message="${user_message//\"/\\\"}"
            printf '{\n  "team_tag": "%s",\n  "action": "%s",\n  "model_type": "%s",\n  "version": "%s",\n  "user_message": "%s"\n}' \
                "$team_tag" "$action" "$model_type" "$version" "$escaped_message"
        else
            printf '{\n  "team_tag": "%s",\n  "action": "%s",\n  "model_type": "%s",\n  "version": "%s"\n}' \
                "$team_tag" "$action" "$model_type" "$version"
        fi
    fi
}

if [ "$action" == "use" ]; then
    # For 'use' action, include model_type, version, and user_message
    json_payload=$(create_json_payload "$team_tag" "$action" "$model_type" "$version" "$user_message")
else
    # For other actions, include only model_type and version
    json_payload=$(create_json_payload "$team_tag" "$action" "$model_type" "$version" "")
fi

# Validate JSON before sending
if command -v python3 &> /dev/null; then
    if ! echo "$json_payload" | python3 -m json.tool > /dev/null 2>&1; then
        echo "❌ Error: Generated invalid JSON payload"
        echo "Payload:"
        echo "$json_payload"
        exit 1
    fi
fi

#echo "📤 Sending JSON Payload:"
echo "$json_payload"

echo "Sending request...."

response=`curl -X POST http://${service_url}/team-profile \
-H "Content-Type: application/json" \
-d "$json_payload"`

echo "Request completed...."
echo -e "\n"

echo "$response" | jq -r '.data.conversation_response.output.message.content[0].text'