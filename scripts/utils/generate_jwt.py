#!/usr/bin/env python3
"""Generate valid JWT tokens for Supabase using JWT_SECRET from .env"""

import base64
import hashlib
import hmac
import json
import os
from pathlib import Path

from dotenv import load_dotenv

# Load environment
env_path = Path(__file__).parent.parent.parent / "docker" / ".env"
load_dotenv(env_path)

jwt_secret = os.getenv("JWT_SECRET")


def create_jwt(payload):
    header = {"alg": "HS256", "typ": "JWT"}

    def b64url(data):
        return base64.urlsafe_b64encode(json.dumps(data).encode()).rstrip(b"=").decode()

    header_b64 = b64url(header)
    payload_b64 = b64url(payload)

    message = f"{header_b64}.{payload_b64}"
    signature = hmac.new(jwt_secret.encode(), message.encode(), hashlib.sha256).digest()
    signature_b64 = base64.urlsafe_b64encode(signature).rstrip(b"=").decode()

    return f"{message}.{signature_b64}"


# Tokens valid until 2030
anon_payload = {"role": "anon", "iss": "supabase", "iat": 1704067200, "exp": 1893456000}
service_payload = {
    "role": "service_role",
    "iss": "supabase",
    "iat": 1704067200,
    "exp": 1893456000,
}

print(f"JWT_SECRET: {jwt_secret}")
print()
print("Copy these to your .env file:")
print()
print(f"ANON_KEY={create_jwt(anon_payload)}")
print()
print(f"SERVICE_ROLE_KEY={create_jwt(service_payload)}")
print(f"SERVICE_ROLE_KEY={create_jwt(service_payload)}")
