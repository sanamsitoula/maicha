"""
Auth Manager — JWT-based authentication with guest/user/admin roles.
Uses the existing users table from Phase 4 schema.
"""
import os
import jwt
import bcrypt
import secrets
from datetime import datetime, timedelta
from agents.shared.database import query, execute

JWT_SECRET = os.getenv("JWT_SECRET", "maicha-secret-change-me-in-production")
JWT_EXPIRY_HOURS = int(os.getenv("JWT_EXPIRY_HOURS", "72"))
ADMIN_SETUP_KEY = os.getenv("ADMIN_SETUP_KEY", "maicha-admin-setup")


def hash_password(password):
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password, password_hash):
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def create_token(user_id, email, role, full_name=None):
    payload = {
        "user_id": str(user_id),
        "email": email,
        "role": role,
        "name": full_name or email.split("@")[0],
        "exp": datetime.utcnow() + timedelta(hours=JWT_EXPIRY_HOURS),
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def decode_token(token):
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        return payload
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        return None


def register_user(email, password, full_name=None, role="user"):
    existing = query("SELECT id FROM users WHERE email = %s", (email,))
    if existing:
        return {"status": "error", "message": "Email already registered"}

    pw_hash = hash_password(password)
    result = execute(
        "INSERT INTO users (email, password_hash, full_name, role, is_active) "
        "VALUES (%s, %s, %s, %s, true) RETURNING id, email, role, full_name",
        (email, pw_hash, full_name or email.split("@")[0], role)
    )
    user = result[0]
    token = create_token(user["id"], user["email"], user["role"], user["full_name"])
    return {
        "status": "ok",
        "user": {"id": str(user["id"]), "email": user["email"], "role": user["role"], "name": user["full_name"]},
        "token": token,
    }


def login_user(email, password):
    users = query(
        "SELECT id, email, password_hash, full_name, role, is_active FROM users WHERE email = %s",
        (email,)
    )
    if not users:
        return {"status": "error", "message": "Invalid email or password"}

    user = users[0]
    if not user["is_active"]:
        return {"status": "error", "message": "Account is deactivated"}

    if not verify_password(password, user["password_hash"]):
        return {"status": "error", "message": "Invalid email or password"}

    execute(
        "UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE id = %s",
        (user["id"],)
    )

    token = create_token(user["id"], user["email"], user["role"], user["full_name"])
    return {
        "status": "ok",
        "user": {"id": str(user["id"]), "email": user["email"], "role": user["role"], "name": user["full_name"]},
        "token": token,
    }


def create_admin(email, password, full_name=None, setup_key=None):
    if setup_key != ADMIN_SETUP_KEY:
        return {"status": "error", "message": "Invalid setup key"}
    return register_user(email, password, full_name, role="admin")


def get_user_from_token(token):
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    users = query(
        "SELECT id, email, full_name, role, is_active FROM users WHERE id = %s::uuid AND is_active = true",
        (payload["user_id"],)
    )
    if not users:
        return None
    return users[0]


def list_users():
    return query(
        "SELECT id, email, full_name, role, is_active, created_at, updated_at "
        "FROM users ORDER BY created_at DESC"
    )


def update_user_role(user_id, new_role):
    if new_role not in ("guest", "user", "admin"):
        return {"status": "error", "message": "Invalid role"}
    execute("UPDATE users SET role = %s, updated_at = CURRENT_TIMESTAMP WHERE id = %s::uuid", (new_role, user_id))
    return {"status": "ok", "user_id": user_id, "role": new_role}


def deactivate_user(user_id):
    execute("UPDATE users SET is_active = false, updated_at = CURRENT_TIMESTAMP WHERE id = %s::uuid", (user_id,))
    return {"status": "ok", "user_id": user_id, "deactivated": True}


def create_guest_token():
    guest_id = f"guest-{secrets.token_hex(8)}"
    payload = {
        "user_id": guest_id,
        "email": f"{guest_id}@guest",
        "role": "guest",
        "name": "Guest",
        "exp": datetime.utcnow() + timedelta(hours=24),
        "iat": datetime.utcnow(),
    }
    return {
        "status": "ok",
        "user": {"id": guest_id, "email": payload["email"], "role": "guest", "name": "Guest"},
        "token": jwt.encode(payload, JWT_SECRET, algorithm="HS256"),
    }
