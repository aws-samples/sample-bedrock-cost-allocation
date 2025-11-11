"""
AIP Manager - Helper class for managing Application Inference Profiles
"""

import boto3
import json
from typing import Dict, Any, Optional, List
from botocore.exceptions import ClientError


class AIPManager:
    """Manages Application Inference Profiles for multi-tenant applications"""
    
    def __init__(self, bedrock_client: boto3.client):
        self.bedrock_client = bedrock_client
    
    def list_aips(self, tags: Dict[str, str] = None) -> List[Dict[str, Any]]:
        """
        List Application Inference Profiles

        Args:
            tags: Optional tags to filter by

        Returns:
            List of AIP information
        """
        try:
            # Use typeEquals parameter to only get APPLICATION profiles
            response = self.bedrock_client.list_inference_profiles(
                typeEquals='APPLICATION'
            )
            aips = []

            for profile in response.get('inferenceProfileSummaries', []):
                aips.append({
                    'name': profile['inferenceProfileName'],
                    'arn': profile['inferenceProfileArn'],
                    'status': profile['status'],
                    'description': profile.get('description', ''),
                    'createdAt': profile.get('createdAt'),
                    'updatedAt': profile.get('updatedAt')
                })

            return aips

        except ClientError as e:
            raise Exception(f"Error listing AIPs: {str(e)}")
    
    def delete_aip(self, aip_identifier: str) -> bool:
        """
        Delete an Application Inference Profile
        
        Args:
            aip_identifier: AIP name or ARN
            
        Returns:
            True if successful
        """
        try:
            self.bedrock_client.delete_inference_profile(
                inferenceProfileIdentifier=aip_identifier
            )
            return True
            
        except ClientError as e:
            raise Exception(f"Error deleting AIP {aip_identifier}: {str(e)}")
    
    def get_aip_info(self, aip_identifier: str) -> Dict[str, Any]:
        """
        Get detailed information about an AIP
        
        Args:
            aip_identifier: AIP name or ARN
            
        Returns:
            AIP details
        """
        try:
            response = self.bedrock_client.get_inference_profile(
                inferenceProfileIdentifier=aip_identifier
            )
            
            return {
                'name': response['inferenceProfileName'],
                'arn': response['inferenceProfileArn'],
                'status': response['status'],
                'description': response.get('description', ''),
                'modelSource': response['modelSource'],
                'createdAt': response.get('createdAt'),
                'updatedAt': response.get('updatedAt')
            }
            
        except ClientError as e:
            raise Exception(f"Error getting AIP info for {aip_identifier}: {str(e)}")
    
    def check_aip_exists(self, name: str) -> Optional[str]:
        """
        Check if AIP exists by name and return its ARN

        Note: AWS Bedrock API doesn't support querying by name directly,
        so we list all APPLICATION profiles and search for a match.

        Args:
            name: AIP name to search for

        Returns:
            AIP ARN if exists, None otherwise
        """
        try:
            # List all APPLICATION profiles and search by name
            all_aips = self.list_aips()

            # Find AIP with matching name (case-sensitive)
            for aip in all_aips:
                if aip['name'] == name:
                    return aip['arn']

            # No match found
            return None

        except Exception as e:
            # Log the error instead of silently swallowing it
            print(f"⚠️ Warning: Error checking if AIP '{name}' exists: {str(e)}")
            print(f"   This may cause duplicate AIPs to be created.")
            # Return None to allow the caller to create a new AIP if needed
            return None
