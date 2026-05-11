"""
Auth middleware — FastAPI dependencies for role-based access.
"""
from fastapi import Header, HTTPException, Depends
from typing import Optional
from agents.shared.auth_manager import decode_token


def get_current_user(authorization: Optional[str] = Header(None)):
    """Extract user from JWT token. Returns None for guests."""
    if not authorization:
        return {"role": "guest", "user_id": None, "email": None, "name": "Guest"}

    token = authorization.replace("Bearer ", "") if authorization.startswith("Bearer ") else authorization
    payload = decode_token(token)
    if not payload:
        return {"role": "guest", "user_id": None, "email": None, "name": "Guest"}

    return {
        "role": payload.get("role", "guest"),
        "user_id": payload.get("user_id"),
        "email": payload.get("email"),
        "name": payload.get("name", "User"),
    }


def require_user(current_user: dict = Depends(get_current_user)):
    """Require at least 'user' role."""
    if current_user["role"] == "guest":
        raise HTTPException(status_code=401, detail="Login required")
    return current_user


def require_admin(current_user: dict = Depends(get_current_user)):
    """Require 'admin' role."""
    if current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    return current_user
