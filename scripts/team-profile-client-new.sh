#############################################################################
# Script Name: team-profile-client.sh
# Description: This script is consumer script for the application deployed on EKS cluster for application inference profile.
#
# Author: Omkar Deshmane
# Date: April 2025
#
# Usage: ./scripts/[script_name.sh]
#
#############################################################################
#!/bin/bash

# Define valid actions and team tags
valid_actions=("create" "delete" "get" "use")
valid_teams=("teama" "teamb")

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

# Clear screen
clear

echo "Welcome to Team Profile API Client"
echo "================================="

# Display available actions
echo "Available actions:"
echo "-----------------"
for action in "${valid_actions[@]}"; do
    echo "- $action"
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

# Add this new section after team tag validation
# If action is 'USE', ask for additional user prompt input
if [ "$action" == "use" ]; then
    echo -e "\nAction 'USE' requires a user prompt."
    while true; do
        read -p "Enter your prompt/question: " user_prompt
        if [ -n "$user_prompt" ]; then
            break
        else
            echo "Error: User prompt cannot be empty for 'USE' action."
        fi
    done
fi

# Ask for version
read -p "Enter version (e.g., 1.0): " version

# Make the API call
service_url=$(kubectl get svc inferencepoc-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

echo -e "\nService url is $service_url"
echo -e "\nMaking API call..."
curl -X POST http://${service_url}/team-profile \
-H "Content-Type: application/json" \
-d '{
"team_tag": "'$team_tag'",
"action": "'$action'",
"version": "'$version'"
}'

if [ "$action" == "use" ]; then
    # Include user prompt for USE action
    curl -X POST http://${service_url}/team-profile \
    -H "Content-Type: application/json" \
    -d '{
    "team_tag": "'$team_tag'",
    "action": "'$action'",
    "version": "'$version'",
    "user_prompt": "'$user_prompt'"
    }'
else
    # Standard payload for other actions
    curl -X POST http://${service_url}/team-profile \
    -H "Content-Type: application/json" \
    -d '{
    "team_tag": "'$team_tag'",
    "action": "'$action'",
    "version": "'$version'"
    }'
fi

echo -e "\n"
