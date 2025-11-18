# Static configuration values
Region = 'us-west-2'
ModelId = 'us.amazon.nova-pro-v1:0'
Prompt = 'hello'

# Updated tags for Tenant A (for Lab 02 update exercise)
tenant_a_tags = [
    {'key': 'TenantId', 'value': 'tenant-a'},
    {'key': 'BusinessType', 'value': 'B2B-Tech'},
    {'key': 'Environment', 'value': 'development'},  # Changed from production to development
    {'key': 'CostCenter', 'value': 'marketing-ai-platform'},
    {'key': 'UpdatedAt', 'value': '2025-01-16'}  # New tag to show update
]

# Updated tags for Tenant B (for Lab 02 practice exercise)
tenant_b_tags = [
    {'key': 'TenantId', 'value': 'tenant-b'},
    {'key': 'BusinessType', 'value': 'B2C-Retail'},
    {'key': 'Environment', 'value': 'development'},  # Changed from production to development
    {'key': 'CostCenter', 'value': 'marketing-ai-platform'},
    {'key': 'UpdatedAt', 'value': '2025-01-16'}  # New tag to show update
]