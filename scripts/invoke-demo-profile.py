#!/usr/bin/env python3
"""
Invoke a Bedrock application inference profile for testing
Usage: python3 invoke-demo-profile.py <tenant-id>

This script is called by cron to test inference profiles periodically.
"""

import boto3
import json
import sys
from datetime import datetime

def invoke_profile(tenant_id):
    """Invoke the inference profile for a given tenant"""

    # Load profiles from JSON
    try:
        with open('/root/demo-profiles.json', 'r') as f:
            profiles = json.load(f)
    except Exception as e:
        print(f"Error loading profiles: {e}")
        return False

    # Find the profile ARN for this tenant
    profile_arn = None
    profile_name = None
    for tid, pname, parn in profiles:
        if tid == tenant_id:
            profile_arn = parn
            profile_name = pname
            break

    if not profile_arn:
        print(f"Profile not found for tenant: {tenant_id}")
        return False

    print(f"[{datetime.now().isoformat()}] Invoking profile for {tenant_id}")
    print(f"Profile Name: {profile_name}")
    print(f"Profile ARN: {profile_arn}")

    # Invoke the model
    try:
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

        print(f"✅ Success!")
        print(f"Response: {output_text}")
        print(f"Input tokens: {input_tokens}")
        print(f"Output tokens: {output_tokens}")
        print(f"Total tokens: {input_tokens + output_tokens}")

        return True

    except Exception as e:
        print(f"❌ Error invoking model: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 invoke-demo-profile.py <tenant-id>")
        print("Example: python3 invoke-demo-profile.py tenant-a-demo")
        sys.exit(1)

    tenant_id = sys.argv[1]
    success = invoke_profile(tenant_id)
    sys.exit(0 if success else 1)
