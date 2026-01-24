import requests

# Login to get token
base_url = "http://127.0.0.1:8000"
login_data = {"username_or_email": "trung1", "password": "1"}
# Try default credentials or ask user? I'll try a common one or create a user.
# Actually I don't know the credentials.
# I can try to register a new user or just modify the script to print response if 401.

# Wait, I can't guess password.
# But I can check the backend logs or DB? No.
# I will try to use the 'check_schema.py' approach by inspecting the OpenAPI docs which are public!

response = requests.get(f"{base_url}/openapi.json")
if response.status_code == 200:
    data = response.json()
    schemas = data.get("components", {}).get("schemas", {})
    conv_schema = schemas.get("Conversation", {})
    print("Conversation Schema Properties:", conv_schema.get("properties", {}).keys())
else:
    print("Failed to fetch OpenAPI:", response.status_code)
