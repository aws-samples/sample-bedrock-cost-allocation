#!/usr/bin/env python3
"""
Invoke a Bedrock application inference profile for testing
Usage: python3 invoke-demo-profile.py <tenant-id>

This script is called by cron to test inference profiles periodically.
Creates profiles if they don't exist.
"""

import boto3
import json
import sys
import os
from datetime import datetime

def log(message):
    """Log with timestamp"""
    timestamp = datetime.now().isoformat()
    formatted_msg = f"[{timestamp}] {message}"
    print(formatted_msg)
    
    # Also log to file (don't fail if can't write)
    try:
        with open('/var/log/bedrock-profiles.log', 'a') as f:
            f.write(formatted_msg + '\n')
    except:
        pass  # Continue if can't write to log file

def create_profile_if_needed(tenant_id):
    """Create APPLICATION inference profile if it doesn't exist"""
    profile_name = f"{tenant_id}-sonnet-4_0"
    
    try:
        client = boto3.client('bedrock', region_name='us-west-2')
        log(f"🔍 Checking if profile exists: {profile_name}")
        
        # Check if profile already exists
        try:
            response = client.list_inference_profiles(typeEquals='APPLICATION')
            existing_profiles = {p['inferenceProfileName']: p['inferenceProfileArn'] 
                               for p in response.get('inferenceProfileSummaries', [])}
            
            log(f"📊 Found {len(existing_profiles)} APPLICATION profiles in Bedrock")
            
            if profile_name in existing_profiles:
                log(f"✅ Profile {profile_name} already exists in Bedrock")
                log(f"   ARN: {existing_profiles[profile_name]}")
                return existing_profiles[profile_name]
            else:
                log(f"❌ Profile {profile_name} not found in Bedrock - will create")
                
        except Exception as e:
            log(f"⚠️  Warning: Could not list existing profiles: {e}")
        
        # Create new APPLICATION inference profile
        log(f"🏗️  Creating APPLICATION inference profile: {profile_name}")
        
        # Get AWS account ID dynamically
        sts_client = boto3.client('sts', region_name='us-west-2')
        account_id = sts_client.get_caller_identity()['Account']
        
        # Construct CRIS system inference profile ARN with dynamic account ID
        model_arn = f"arn:aws:bedrock:us-west-2:{account_id}:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0"
        log(f"📋 Using system inference profile ARN: {model_arn}")
        
        response = client.create_inference_profile(
            inferenceProfileName=profile_name,
            description=f'Application inference profile for {tenant_id}',
            modelSource={
                'copyFrom': model_arn
            },
            tags=[
                {'key': 'TenantId', 'value': tenant_id},
                {'key': 'Purpose', 'value': 'workshop-cost-demo'},
                {'key': 'Type', 'value': 'APPLICATION'}
            ]
        )
        
        profile_arn = response['inferenceProfileArn']
        status = response.get('status', 'Unknown')
        log(f"✅ Successfully created APPLICATION profile: {profile_name}")
        log(f"   ARN: {profile_arn}")
        log(f"   Status: {status}")
        
        # Verify it was created by checking Bedrock again
        try:
            verify_response = client.list_inference_profiles(typeEquals='APPLICATION')
            verify_profiles = {p['inferenceProfileName']: p for p in verify_response.get('inferenceProfileSummaries', [])}
            
            if profile_name in verify_profiles:
                profile_info = verify_profiles[profile_name]
                log(f"✅ Verified profile exists in Bedrock:")
                log(f"   Name: {profile_info['inferenceProfileName']}")
                log(f"   Type: {profile_info.get('type', 'Unknown')}")
                log(f"   Status: {profile_info.get('status', 'Unknown')}")
            else:
                log(f"⚠️  Warning: Profile created but not found in verification list")
        except Exception as e:
            log(f"⚠️  Warning: Could not verify profile creation: {e}")
        
        # Update the profiles JSON file
        update_profiles_file(tenant_id, profile_name, profile_arn)
        
        return profile_arn
        
    except Exception as e:
        log(f"❌ Failed to create profile {profile_name}: {str(e)}")
        import traceback
        log(f"🔍 Full error traceback: {traceback.format_exc()}")
        return None

def update_profiles_file(tenant_id, profile_name, profile_arn):
    """Update or create the profiles JSON file"""
    profiles_file = '/root/demo-profiles.json'
    
    log(f"📁 Updating profiles file: {profiles_file}")
    
    # Load existing profiles
    profiles = []
    if os.path.exists(profiles_file):
        try:
            with open(profiles_file, 'r') as f:
                profiles = json.load(f)
            log(f"📖 Loaded {len(profiles)} existing profiles from file")
        except Exception as e:
            log(f"⚠️  Warning: Could not load existing profiles file: {e}")
            profiles = []
    else:
        log(f"📄 Creating new profiles file")
    
    # Update or add this tenant's profile
    updated = False
    for i, (tid, pname, parn) in enumerate(profiles):
        if tid == tenant_id:
            profiles[i] = (tenant_id, profile_name, profile_arn)
            log(f"🔄 Updated existing entry for {tenant_id}")
            updated = True
            break
    
    if not updated:
        profiles.append((tenant_id, profile_name, profile_arn))
        log(f"➕ Added new entry for {tenant_id}")
    
    # Save updated profiles
    try:
        with open(profiles_file, 'w') as f:
            json.dump(profiles, f, indent=2)
        log(f"💾 Successfully saved {len(profiles)} profiles to file")
    except Exception as e:
        log(f"❌ Failed to save profiles file: {e}")

def load_or_create_profile(tenant_id):
    """Load profile ARN from file or create if needed"""
    profiles_file = '/root/demo-profiles.json'
    
    log(f"🔍 Looking for profile for tenant: {tenant_id}")
    
    # Try to load from existing file first
    if os.path.exists(profiles_file):
        try:
            with open(profiles_file, 'r') as f:
                profiles = json.load(f)
            
            for tid, pname, parn in profiles:
                if tid == tenant_id:
                    log(f"📁 Found profile in cache: {pname}")
                    log(f"   ARN: {parn}")
                    return pname, parn
        except Exception as e:
            log(f"⚠️  Warning: Could not load profiles file: {e}")
    
    log(f"❌ Profile not found in cache for {tenant_id}")
    
    # Create profile if not found
    profile_arn = create_profile_if_needed(tenant_id)
    if profile_arn:
        profile_name = f"{tenant_id}-sonnet-4_0"
        log(f"✅ Successfully obtained profile: {profile_name}")
        return profile_name, profile_arn
    
    log(f"❌ Failed to create or obtain profile for {tenant_id}")
    return None, None

def invoke_profile(tenant_id):
    """Invoke the inference profile for a given tenant"""
    
    log(f"🚀 Starting profile invocation for tenant: {tenant_id}")
    
    # Load or create profile
    profile_name, profile_arn = load_or_create_profile(tenant_id)
    
    if not profile_arn:
        log(f"❌ Could not find or create profile for tenant: {tenant_id}")
        return False

    log(f"📋 Profile details:")
    log(f"   Name: {profile_name}")
    log(f"   ARN: {profile_arn}")

    # Invoke the model
    try:
        log(f"🔄 Invoking Bedrock model...")
        bedrock_runtime = boto3.client('bedrock-runtime', region_name='us-west-2')

        response = bedrock_runtime.converse(
            modelId=profile_arn,
            messages=[{
                "role": "user",
                "content": [{"text": "Hello! Please respond with exactly 5 words."}]
            }]
        )

        output_text = response['output']['message']['content'][0]['text']
        input_tokens = response['usage']['inputTokens']
        output_tokens = response['usage']['outputTokens']
        total_tokens = input_tokens + output_tokens

        log(f"✅ Invocation successful!")
        log(f"   Response: {output_text}")
        log(f"   Input tokens: {input_tokens}")
        log(f"   Output tokens: {output_tokens}")
        log(f"   Total tokens: {total_tokens}")

        return True

    except Exception as e:
        log(f"❌ Error invoking model: {e}")
        import traceback
        log(f"🔍 Full error traceback: {traceback.format_exc()}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        log("❌ Missing tenant ID argument")
        print("Usage: python3 invoke-demo-profile.py <tenant-id>")
        print("Example: python3 invoke-demo-profile.py tenant-a-demo")
        sys.exit(1)

    tenant_id = sys.argv[1]
    log(f"🎯 Starting Bedrock profile test for tenant: {tenant_id}")
    log("=" * 60)
    
    success = invoke_profile(tenant_id)
    
    log("=" * 60)
    if success:
        log(f"🎉 Profile test completed successfully for {tenant_id}")
    else:
        log(f"💥 Profile test failed for {tenant_id}")
    
    sys.exit(0 if success else 1)
