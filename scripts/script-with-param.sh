#!/bin/bash

#############################################################################
# Script Name: team-profile-client-params.sh
# Description: Parameter-based consumer script for the application deployed on EKS cluster for application inference profile.
#
# Author: Omkar Deshmane
# Date: April 2025
#
# Usage: ./team-profile-client-params.sh -a <action> -t <team> -v <version>
#
#############################################################################

# Define valid actions and team tags
valid_actions=("create" "delete" "get" "use")
valid_teams=("teama" "teamb")

# Function to validate action
validate_action() {
    local input_action=$1
    for valid_action in "${valid_actions[@]}"; do
        if [ "$input_action" == "$valid_action" ]; then
            return 0
        fi
    done
    return 1
}

# Function to validate team tag
validate_team() {
    local input_team=$1
    for valid_team in "${valid_teams[@]}"; do
        if [ "$input_team" == "$valid_team" ]; then
            return 0
        fi
    done
    return 1
}

# Function to show usage
show_usage() {
    echo "Usage: $0 -a <action> -t <team> -v <version>"
    echo "Options:"
    echo "  -a <action>   Action to perform (${valid_actions[*]})"
    echo "  -t <team>     Team tag (${valid_teams[*]})"
    echo "  -v <version>  Version (e.g., 1.0)"
    echo "  -h            Show this help message"
}

# Parse command line arguments
while getopts "a:t:v:h" opt; do
    case $opt in
        a) action="$OPTARG" ;;
        t) team_tag="$OPTARG" ;;
        v) version="$OPTARG" ;;
        h) show_usage; exit 0 ;;
        *) show_usage; exit 1 ;;
    esac
done

# Check if all required parameters are provided
if [ -z "$action" ] || [ -z "$team_tag" ] || [ -z "$version" ]; then
    echo "Error: Missing required parameters"
    show_usage
    exit 1
fi

# Validate action
if ! validate_action "$action"; then
    echo "Error: Invalid action '$action'. Valid actions: ${valid_actions[*]}"
    exit 1
fi

# Validate team tag
if ! validate_team "$team_tag"; then
    echo "Error: Invalid team tag '$team_tag'. Valid teams: ${valid_teams[*]}"
    exit 1
fi

# Get service URL
service_url=$(kubectl get svc inferencepoc-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

echo "Service url is $service_url"
echo "Making API call..."

# Make the API call 100 times
for i in {1..100}; do
    echo "Request $i:"
    curl -X POST http://${service_url}/team-profile \
    -H "Content-Type: application/json" \
    -d '{
    "team_tag": "'$team_tag'",
    "action": "'$action'",
    "version": "'$version'"
    }'
    echo
done
