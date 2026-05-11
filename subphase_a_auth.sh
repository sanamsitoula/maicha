#!/bin/bash
set -e
echo "=== Sub-phase A: Auth + Role System ==="

BASE="/opt/ai-server"
AGENTS="$BASE/agents"
cd "$BASE"

# ============================================
# Step 1: Add auth dependencies
# ============================================
cat > "$AGENTS/requirements.txt" << 'EOF'
fastapi==0.115.0
uvicorn==0.30.6
psycopg2-binary==2.9.9
httpx==0.27.2
python-dotenv==1.0.1
pydantic==2.9.2
PyJWT==2.9.0
bcrypt==4.2.0
python-multipart==0.0.12
EOF

echo "Updated requirements.txt with auth packages"

# ============================================
# Step 2: Create auth_manager.py
# ============================================
cat > "$AGENTS/shared/auth_manager.py" << 'EOF'
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
EOF

echo "Created auth_manager.py"

# ============================================
# Step 3: Create auth middleware for FastAPI
# ============================================
cat > "$AGENTS/shared/auth_middleware.py" << 'EOF'
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
EOF

echo "Created auth_middleware.py"

# ============================================
# Step 4: Rewrite api.py with auth integrated
# ============================================
# Back up current api.py
cp "$AGENTS/api.py" "$AGENTS/api.py.bak"

cat > "$AGENTS/api.py" << 'APEOF'
"""
Maicha AI Platform — FastAPI Backend v2
Auth + Models + Settings + Notifications + Translation + Agents
"""
import os
import json
import time
import secrets
import httpx
from fastapi import FastAPI, HTTPException, Header, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any

from agents.shared.database import query, execute
from agents.shared.auth_manager import (
    register_user, login_user, create_admin, create_guest_token,
    get_user_from_token, list_users, update_user_role, deactivate_user,
)
from agents.shared.auth_middleware import get_current_user, require_user, require_admin
from agents.shared.model_manager import (
    ollama_list, ollama_pull, ollama_delete, ollama_model_info,
    add_paid_model, remove_model, list_registered_models,
    set_default_model, get_default_model, get_model_config, PROVIDERS,
    ensure_model_table, seed_defaults,
)
from agents.shared.settings_manager import (
    get_all_settings, get_category_settings, set_setting,
    save_smtp_config, save_telegram_config, save_slack_config,
    save_discord_config, save_whatsapp_config,
    test_smtp, test_telegram, test_slack, test_discord, test_whatsapp,
    ensure_settings_table,
)
from agents.shared.notification_sender import (
    send_email, send_telegram, send_slack, send_discord,
    send_whatsapp, send_notification,
)
from agents.shared.translator import (
    translate_to_nepali, translate_to_english, translate, generate_nepali_content,
)
from agents.restaurant.agent import create_restaurant_agent
from agents.real_estate.agent import create_real_estate_agent
from agents.social_media.agent import create_social_media_agent
from agents.marketing.agent import create_marketing_agent
from agents.video.agent import create_video_agent
from agents.orchestrator.hermes_agent import create_hermes_agent

app = FastAPI(
    title="Maicha AI Platform",
    description="AI automation with auth, agents, models, settings, notifications",
    version="2.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup():
    ensure_model_table()
    seed_defaults()
    ensure_settings_table()


# ── Agent instances ──
agents_cache = {}

def get_agent(agent_type):
    if agent_type not in agents_cache:
        factories = {
            "restaurant": create_restaurant_agent,
            "real-estate": create_real_estate_agent,
            "social-media": create_social_media_agent,
            "marketing": create_marketing_agent,
            "video": create_video_agent,
            "hermes": create_hermes_agent,
        }
        if agent_type not in factories:
            raise HTTPException(status_code=404, detail=f"Unknown agent: {agent_type}")
        agents_cache[agent_type] = factories[agent_type]()
    return agents_cache[agent_type]


# ══════════════════════════════════════════
# AUTH ROUTES (open to everyone)
# ══════════════════════════════════════════

class RegisterRequest(BaseModel):
    email: str
    password: str
    full_name: Optional[str] = None

class LoginRequest(BaseModel):
    email: str
    password: str

class AdminSetupRequest(BaseModel):
    email: str
    password: str
    full_name: Optional[str] = None
    setup_key: str


@app.post("/auth/register")
def api_register(req: RegisterRequest):
    """Register a new user account."""
    return register_user(req.email, req.password, req.full_name)

@app.post("/auth/login")
def api_login(req: LoginRequest):
    """Login and get JWT token."""
    return login_user(req.email, req.password)

@app.post("/auth/guest")
def api_guest():
    """Get a guest token (no registration needed)."""
    return create_guest_token()

@app.post("/auth/admin-setup")
def api_admin_setup(req: AdminSetupRequest):
    """Create the first admin account (requires setup key from .env)."""
    return create_admin(req.email, req.password, req.full_name, req.setup_key)

@app.get("/auth/me")
def api_me(user: dict = Depends(get_current_user)):
    """Get current user info from token."""
    return {"user": user}


# ══════════════════════════════════════════
# ADMIN ROUTES (admin only)
# ══════════════════════════════════════════

class UpdateRoleRequest(BaseModel):
    user_id: str
    role: str

@app.get("/admin/users", dependencies=[Depends(require_admin)])
def api_list_users():
    """List all users (admin only)."""
    return {"users": list_users()}

@app.post("/admin/users/role", dependencies=[Depends(require_admin)])
def api_update_role(req: UpdateRoleRequest):
    """Update a user's role (admin only)."""
    return update_user_role(req.user_id, req.role)

@app.delete("/admin/users/{user_id}", dependencies=[Depends(require_admin)])
def api_deactivate_user(user_id: str):
    """Deactivate a user (admin only)."""
    return deactivate_user(user_id)


# ══════════════════════════════════════════
# CORE ROUTES (open to all including guests)
# ══════════════════════════════════════════

@app.get("/")
def root():
    return {"status": "running", "service": "Maicha AI Platform", "version": "2.0.0"}

@app.get("/health")
def health():
    try:
        query("SELECT 1")
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {str(e)}"
    # Check n8n
    n8n_status = "unknown"
    try:
        resp = httpx.get("http://n8n:5678/healthz", timeout=3.0)
        n8n_status = "running" if resp.status_code == 200 else "error"
    except Exception:
        n8n_status = "unreachable"
    return {"status": "healthy", "database": db_status, "n8n": n8n_status, "agents_loaded": list(agents_cache.keys())}

@app.get("/agents")
def api_list_agents():
    return {"agents": [
        {"name": "restaurant", "description": "Food orders, menu, reservations"},
        {"name": "real-estate", "description": "Property listings, inquiries, lead qualification"},
        {"name": "social-media", "description": "Content creation, hashtags, scheduling"},
        {"name": "marketing", "description": "Ad copy, emails, blog posts, campaigns"},
        {"name": "video", "description": "Video scripts, media production"},
        {"name": "hermes", "description": "Advanced orchestrator — multi-agent + Nepali translation"},
    ]}


# ══════════════════════════════════════════
# CHAT (guests can chat, users get history saved)
# ══════════════════════════════════════════

class ChatRequest(BaseModel):
    message: str
    agent_type: str
    model: Optional[str] = None
    session_id: Optional[str] = None

class ChatResponse(BaseModel):
    response: str
    agent_type: str
    model_used: str
    session_id: str
    elapsed_seconds: float


@app.post("/chat", response_model=ChatResponse)
def chat_endpoint(req: ChatRequest, user: dict = Depends(get_current_user)):
    start = time.time()
    agent = get_agent(req.agent_type)
    model_name = req.model or os.getenv("DEFAULT_MODEL", "qwen3:8b")

    if req.session_id == "new" or req.session_id is None:
        agent.reset_conversation()
        session_id = secrets.token_hex(8)
    else:
        session_id = req.session_id

    model_cfg = get_model_config(model_name)
    if model_cfg:
        agent.model = model_name

    response = agent.process_message(req.message)
    elapsed = round(time.time() - start, 2)

    return ChatResponse(
        response=response, agent_type=req.agent_type,
        model_used=model_name, session_id=session_id,
        elapsed_seconds=elapsed,
    )


# ══════════════════════════════════════════
# MODEL MANAGEMENT (admin for write, all for read)
# ══════════════════════════════════════════

class PullModelRequest(BaseModel):
    name: str

class AddPaidModelRequest(BaseModel):
    name: str
    provider: str
    model_id: str
    api_key: str
    api_base_url: Optional[str] = None

class SetDefaultRequest(BaseModel):
    name: str


@app.get("/models")
def api_get_models():
    registered = list_registered_models()
    ollama_models = ollama_list()
    return {
        "registered": registered,
        "ollama_installed": ollama_models if not isinstance(ollama_models, dict) else [],
        "providers": {k: {"label": v["label"], "default_models": v["default_models"]} for k, v in PROVIDERS.items()},
        "default": get_default_model(),
    }

@app.get("/models/ollama")
def api_get_ollama():
    return {"models": ollama_list()}

@app.post("/models/ollama/pull", dependencies=[Depends(require_admin)])
def api_pull_model(req: PullModelRequest):
    return ollama_pull(req.name)

@app.delete("/models/ollama/{model_name}", dependencies=[Depends(require_admin)])
def api_delete_ollama(model_name: str):
    return ollama_delete(model_name)

@app.get("/models/ollama/{model_name}/info")
def api_model_info(model_name: str):
    return ollama_model_info(model_name)

@app.post("/models/paid", dependencies=[Depends(require_admin)])
def api_add_paid(req: AddPaidModelRequest):
    return add_paid_model(req.name, req.provider, req.model_id, req.api_key, req.api_base_url)

@app.delete("/models/{model_name}", dependencies=[Depends(require_admin)])
def api_delete_model(model_name: str):
    return remove_model(model_name)

@app.post("/models/default", dependencies=[Depends(require_admin)])
def api_set_default(req: SetDefaultRequest):
    return set_default_model(req.name)

@app.get("/models/providers")
def api_get_providers():
    return {"providers": {k: {"label": v["label"], "default_models": v["default_models"]} for k, v in PROVIDERS.items()}}


# ══════════════════════════════════════════
# SETTINGS (admin only for write, admin for read)
# ══════════════════════════════════════════

class SmtpConfigRequest(BaseModel):
    host: str
    port: int = 587
    username: str
    password: str
    from_email: str
    use_tls: bool = True

class TelegramConfigRequest(BaseModel):
    bot_token: str
    default_chat_id: Optional[str] = None

class SlackConfigRequest(BaseModel):
    webhook_url: str
    default_channel: Optional[str] = None

class DiscordConfigRequest(BaseModel):
    webhook_url: str

class WhatsAppConfigRequest(BaseModel):
    phone_number_id: str
    access_token: str
    verify_token: Optional[str] = None

class SettingRequest(BaseModel):
    category: str
    key: str
    value: str
    is_secret: bool = False


@app.get("/settings", dependencies=[Depends(require_admin)])
def api_get_settings():
    return {
        "settings": get_all_settings(mask_secrets=True),
        "categories": {
            "smtp": {"label": "Email (SMTP)", "description": "Send emails via SMTP server", "fields": [
                {"key": "host", "label": "SMTP Host", "type": "text", "placeholder": "smtp.gmail.com"},
                {"key": "port", "label": "Port", "type": "number", "placeholder": "587"},
                {"key": "username", "label": "Username", "type": "text", "placeholder": "you@gmail.com"},
                {"key": "password", "label": "Password", "type": "password"},
                {"key": "from_email", "label": "From Email", "type": "text", "placeholder": "you@gmail.com"},
                {"key": "use_tls", "label": "Use TLS", "type": "toggle", "default": "True"},
            ]},
            "telegram": {"label": "Telegram", "description": "Telegram bot notifications", "fields": [
                {"key": "bot_token", "label": "Bot Token", "type": "password", "placeholder": "123456:ABC-DEF..."},
                {"key": "default_chat_id", "label": "Default Chat ID", "type": "text", "placeholder": "1234567890"},
            ]},
            "slack": {"label": "Slack", "description": "Slack webhook notifications", "fields": [
                {"key": "webhook_url", "label": "Webhook URL", "type": "password", "placeholder": "https://hooks.slack.com/services/..."},
                {"key": "default_channel", "label": "Default Channel", "type": "text", "placeholder": "#general"},
            ]},
            "discord": {"label": "Discord", "description": "Discord webhook notifications", "fields": [
                {"key": "webhook_url", "label": "Webhook URL", "type": "password", "placeholder": "https://discord.com/api/webhooks/..."},
            ]},
            "whatsapp": {"label": "WhatsApp", "description": "WhatsApp Business API", "fields": [
                {"key": "phone_number_id", "label": "Phone Number ID", "type": "text"},
                {"key": "access_token", "label": "Access Token", "type": "password"},
                {"key": "verify_token", "label": "Verify Token", "type": "password"},
            ]},
        }
    }

@app.get("/settings/{category}", dependencies=[Depends(require_admin)])
def api_get_category(category: str):
    return {"category": category, "settings": get_category_settings(category)}

@app.post("/settings", dependencies=[Depends(require_admin)])
def api_save_setting(req: SettingRequest):
    set_setting(req.category, req.key, req.value, req.is_secret)
    return {"status": "saved"}

@app.post("/settings/smtp", dependencies=[Depends(require_admin)])
def api_smtp(req: SmtpConfigRequest):
    return save_smtp_config(req.host, req.port, req.username, req.password, req.from_email, req.use_tls)

@app.post("/settings/telegram", dependencies=[Depends(require_admin)])
def api_telegram(req: TelegramConfigRequest):
    return save_telegram_config(req.bot_token, req.default_chat_id)

@app.post("/settings/slack", dependencies=[Depends(require_admin)])
def api_slack(req: SlackConfigRequest):
    return save_slack_config(req.webhook_url, req.default_channel)

@app.post("/settings/discord", dependencies=[Depends(require_admin)])
def api_discord(req: DiscordConfigRequest):
    return save_discord_config(req.webhook_url)

@app.post("/settings/whatsapp", dependencies=[Depends(require_admin)])
def api_whatsapp(req: WhatsAppConfigRequest):
    return save_whatsapp_config(req.phone_number_id, req.access_token, req.verify_token)

@app.post("/settings/smtp/test", dependencies=[Depends(require_admin)])
def api_test_smtp():
    return test_smtp()

@app.post("/settings/telegram/test", dependencies=[Depends(require_admin)])
def api_test_telegram():
    return test_telegram()

@app.post("/settings/slack/test", dependencies=[Depends(require_admin)])
def api_test_slack():
    return test_slack()

@app.post("/settings/discord/test", dependencies=[Depends(require_admin)])
def api_test_discord():
    return test_discord()

@app.post("/settings/whatsapp/test", dependencies=[Depends(require_admin)])
def api_test_whatsapp():
    return test_whatsapp()


# ══════════════════════════════════════════
# NOTIFICATIONS (user+ for send)
# ══════════════════════════════════════════

class SendEmailRequest(BaseModel):
    to_email: str
    subject: str
    body: str
    html_body: Optional[str] = None

class SendNotificationRequest(BaseModel):
    message: str
    channels: Optional[List[str]] = None

class SendWhatsAppRequest(BaseModel):
    to_phone: str
    message: str


@app.post("/notify/email")
def api_send_email(req: SendEmailRequest):
    return send_email(req.to_email, req.subject, req.body, req.html_body)

@app.post("/notify/telegram")
def api_send_telegram(req: SendNotificationRequest):
    return send_telegram(req.message)

@app.post("/notify/slack")
def api_send_slack(req: SendNotificationRequest):
    return send_slack(req.message)

@app.post("/notify/discord")
def api_send_discord(req: SendNotificationRequest):
    return send_discord(req.message)

@app.post("/notify/whatsapp")
def api_send_whatsapp(req: SendWhatsAppRequest):
    return send_whatsapp(req.to_phone, req.message)

@app.post("/notify/all")
def api_send_all(req: SendNotificationRequest):
    return send_notification(req.message, req.channels)


# ══════════════════════════════════════════
# TRANSLATION (open to all)
# ══════════════════════════════════════════

class TranslateRequest(BaseModel):
    text: str
    source_lang: str = "en"
    target_lang: str = "ne"
    model: Optional[str] = None

class NepaliContentRequest(BaseModel):
    topic: str
    content_type: str = "post"
    platform: str = "facebook"
    model: Optional[str] = None


@app.post("/translate")
def api_translate(req: TranslateRequest):
    return translate(req.text, req.source_lang, req.target_lang, req.model)

@app.post("/translate/to-nepali")
def api_to_nepali(req: TranslateRequest):
    return translate_to_nepali(req.text, req.model)

@app.post("/translate/to-english")
def api_to_english(req: TranslateRequest):
    return translate_to_english(req.text, req.model)

@app.post("/content/nepali")
def api_nepali_content(req: NepaliContentRequest):
    return generate_nepali_content(req.topic, req.content_type, req.platform, req.model)


# ══════════════════════════════════════════
# DATA ROUTES (open to all)
# ══════════════════════════════════════════

@app.get("/menu")
def api_menu(category: Optional[str] = None):
    if category:
        items = query("SELECT name, description, category, price, dietary_tags FROM menu_items WHERE is_available = true AND LOWER(category) = LOWER(%s) ORDER BY category, name", (category,))
    else:
        items = query("SELECT name, description, category, price, dietary_tags FROM menu_items WHERE is_available = true ORDER BY category, name")
    return {"menu_items": items, "count": len(items)}

@app.get("/properties")
def api_properties(city: Optional[str] = None, listing_type: Optional[str] = None):
    conditions = ["status = 'active'"]
    params = []
    if city:
        conditions.append("LOWER(city) = LOWER(%s)")
        params.append(city)
    if listing_type:
        conditions.append("LOWER(listing_type) = LOWER(%s)")
        params.append(listing_type)
    where = " AND ".join(conditions)
    props = query(f"SELECT title, description, property_type, listing_type, price, bedrooms, bathrooms, city, state FROM property_listings WHERE {where} ORDER BY created_at DESC LIMIT 20", tuple(params) if params else None)
    return {"properties": props, "count": len(props)}

@app.get("/orders")
def api_orders(status: Optional[str] = None, limit: int = 20):
    if status:
        return {"orders": query("SELECT id, customer_name, status, total, created_at FROM orders WHERE LOWER(status) = LOWER(%s) ORDER BY created_at DESC LIMIT %s", (status, limit))}
    return {"orders": query("SELECT id, customer_name, status, total, created_at FROM orders ORDER BY created_at DESC LIMIT %s", (limit,))}

@app.get("/conversations")
def api_conversations(agent_type: Optional[str] = None, limit: int = 20):
    if agent_type:
        return {"conversations": query("SELECT id, agent_type, title, status, created_at FROM conversations WHERE agent_type = %s ORDER BY created_at DESC LIMIT %s", (agent_type, limit))}
    return {"conversations": query("SELECT id, agent_type, title, status, created_at FROM conversations ORDER BY created_at DESC LIMIT %s", (limit,))}

@app.get("/events")
def api_events(source: Optional[str] = None, limit: int = 50):
    if source:
        return {"events": query("SELECT event_type, source, data, created_at FROM events WHERE source = %s ORDER BY created_at DESC LIMIT %s", (source, limit))}
    return {"events": query("SELECT event_type, source, data, created_at FROM events ORDER BY created_at DESC LIMIT %s", (limit,))}

@app.get("/stats")
def api_stats():
    stats = {}
    for table in ["conversations", "messages", "orders", "reservations", "property_listings", "property_inquiries", "content_queue", "generated_scripts", "media_jobs", "events"]:
        result = query(f"SELECT count(*) as count FROM {table}")
        stats[table] = result[0]["count"]
    # Try n8n stats
    try:
        import psycopg2
        conn = psycopg2.connect(host=os.getenv("POSTGRES_HOST", "postgres"), port=5432, user=os.getenv("POSTGRES_USER"), password=os.getenv("POSTGRES_PASSWORD"), database="n8n")
        cur = conn.cursor()
        cur.execute("SELECT count(*) FROM workflow_entity")
        stats["n8n_workflows"] = cur.fetchone()[0]
        cur.execute("SELECT count(*) FROM execution_entity")
        stats["n8n_executions"] = cur.fetchone()[0]
        cur.close()
        conn.close()
    except Exception:
        stats["n8n_workflows"] = 0
        stats["n8n_executions"] = 0
    return {"stats": stats}


# ══════════════════════════════════════════
# N8N INTEGRATION
# ══════════════════════════════════════════

@app.get("/n8n/workflows")
def api_n8n_workflows():
    import glob
    workflows = []
    for base in ["/opt/ai-server/n8n/workflows", "/app/agents/../n8n/workflows"]:
        for f in sorted(glob.glob(f"{base}/*.json")):
            try:
                with open(f) as fh:
                    data = json.load(fh)
                    name = data.get("name", "Unknown")
                    if not any(w["name"] == name for w in workflows):
                        workflows.append({"file": f.split("/")[-1], "name": name, "description": data.get("description", "")})
            except Exception:
                pass
    n8n_status = "unknown"
    try:
        resp = httpx.get("http://n8n:5678/healthz", timeout=3.0)
        n8n_status = "running" if resp.status_code == 200 else "error"
    except Exception:
        n8n_status = "unreachable"
    return {"workflows": workflows, "n8n_url": f"http://{os.getenv('DOMAIN', 'localhost')}:5678", "n8n_status": n8n_status}


# ══════════════════════════════════════════
# TELEGRAM WEBHOOK (for bot orders)
# ══════════════════════════════════════════

@app.post("/webhook/telegram")
async def telegram_webhook(request: Request):
    """Receive messages from Telegram bot, route to agents, notify Discord."""
    body = await request.json()
    message = body.get("message", {})
    text = message.get("text", "")
    chat_id = str(message.get("chat", {}).get("id", ""))
    user_name = message.get("from", {}).get("first_name", "Customer")

    if not text or not chat_id:
        return {"ok": True}

    execute("INSERT INTO events (event_type, source, data) VALUES (%s, %s, %s)",
            ("telegram_message", "telegram-bot", json.dumps({"chat_id": chat_id, "user": user_name, "text": text})))

    food_keywords = ["order", "menu", "food", "burger", "salad", "cheesecake", "reserve", "book", "table"]
    property_keywords = ["property", "house", "apartment", "rent", "buy", "listing"]

    if text.lower().startswith("/start"):
        reply = f"Welcome {user_name}! I'm Maicha AI.\n\n/menu — View restaurant menu\n/order [items] — Place an order\n/properties — Search listings\n\nOr just type your request!"
    elif text.lower().startswith("/menu"):
        menu = query("SELECT name, price, category FROM menu_items WHERE is_available = true ORDER BY category, name")
        reply = "🍽 *Menu*\n\n" + "\n".join(f"• {i['name']} — ${i['price']}" for i in menu) + "\n\nTo order: /order Neural Burger"
    elif any(kw in text.lower() for kw in food_keywords):
        agent = get_agent("restaurant")
        agent.reset_conversation()
        reply = agent.process_message(f"Customer {user_name}: {text}")
        send_discord(f"🍽 **Telegram Order**\nFrom: {user_name}\nMessage: {text}\nAgent: {reply[:300]}")
    elif any(kw in text.lower() for kw in property_keywords):
        agent = get_agent("real-estate")
        agent.reset_conversation()
        reply = agent.process_message(text)
        send_discord(f"🏠 **Property Inquiry (Telegram)**\nFrom: {user_name}\nMessage: {text}")
    else:
        agent = get_agent("restaurant")
        agent.reset_conversation()
        reply = agent.process_message(text)

    send_telegram(reply, chat_id)
    return {"ok": True}
APEOF

echo "Rewrote api.py with full auth system"

# ============================================
# Step 5: Add JWT_SECRET and ADMIN_SETUP_KEY to .env
# ============================================
if ! grep -q "JWT_SECRET" "$BASE/.env"; then
    JWT=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    ADMIN_KEY=$(python3 -c "import secrets; print(secrets.token_hex(16))")
    cat >> "$BASE/.env" << ENVEOF

# Auth
JWT_SECRET=$JWT
JWT_EXPIRY_HOURS=72
ADMIN_SETUP_KEY=$ADMIN_KEY
ENVEOF
    echo "Added JWT_SECRET and ADMIN_SETUP_KEY to .env"
    echo ""
    echo "IMPORTANT — Save your admin setup key: $ADMIN_KEY"
    echo "You'll need this to create the first admin account."
fi

# Update .env.example
if ! grep -q "JWT_SECRET" "$BASE/.env.example"; then
    cat >> "$BASE/.env.example" << 'ENVEOF'

# Auth
JWT_SECRET=CHANGE_ME_RANDOM_64_CHAR_STRING
JWT_EXPIRY_HOURS=72
ADMIN_SETUP_KEY=CHANGE_ME_USED_TO_CREATE_FIRST_ADMIN
ENVEOF
fi

# ============================================
# Step 6: Add auth env vars to docker-compose fastapi
# ============================================
if ! grep -q "JWT_SECRET" docker-compose.yml; then
    sed -i '/API_KEY=change-me/a\      - JWT_SECRET=${JWT_SECRET}\n      - JWT_EXPIRY_HOURS=${JWT_EXPIRY_HOURS}\n      - ADMIN_SETUP_KEY=${ADMIN_SETUP_KEY}' docker-compose.yml
    echo "Added JWT vars to docker-compose.yml"
fi

# ============================================
# Step 7: Add new proxy routes to nginx
# ============================================
if ! grep -q "location /auth" "$BASE/nginx/nginx.conf"; then
    sed -i '/location \/openapi.json/a\
        location /auth { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Content-Type $http_content_type; }\
        location /admin { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Authorization $http_authorization; }\
        location /webhook { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Content-Type $http_content_type; }' "$BASE/nginx/nginx.conf"
    echo "Added /auth, /admin, /webhook to nginx"
fi

# Also ensure Authorization header is passed for all proxy routes
sed -i 's|proxy_set_header Host $host;|proxy_set_header Host $host; proxy_set_header Authorization $http_authorization;|g' "$BASE/nginx/nginx.conf"

# ============================================
# Step 8: Git commit
# ============================================
git add -A
git commit -m "Sub-phase A: Auth + role system (guest/user/admin)

Features:
- auth_manager.py: JWT auth, bcrypt passwords, guest tokens
- auth_middleware.py: role-based access (get_current_user, require_user, require_admin)
- api.py fully rewritten with auth integrated:
  * POST /auth/register, /auth/login, /auth/guest, /auth/admin-setup
  * GET /auth/me — current user from token
  * Admin-only: model pull/delete, settings config, user management
  * Guest-allowed: chat, explore data, view models
  * /webhook/telegram — receives Telegram messages, routes to agents, notifies Discord
- Stats now include n8n workflow + execution counts from n8n database
- Settings endpoint returns field definitions for UI form generation
- All notification channels in single clean API
- JWT_SECRET + ADMIN_SETUP_KEY in .env
- Nginx updated with /auth, /admin, /webhook routes"

echo ""
echo "=== Sub-phase A Complete ==="
echo ""
echo "Run:"
echo "  cd /opt/ai-server"
echo "  docker compose build fastapi agent-runner"
echo "  docker compose up -d --force-recreate fastapi nginx"
echo "  git push"
echo ""
ADMIN_KEY=$(grep ADMIN_SETUP_KEY "$BASE/.env" | cut -d= -f2)
echo "Then create your admin account:"
echo "  curl -X POST http://localhost:8000/auth/admin-setup -H 'Content-Type: application/json' -d '{\"email\":\"sanam.ctaula@gmail.com\",\"password\":\"YOUR_PASSWORD\",\"full_name\":\"Sanam Sitoula\",\"setup_key\":\"$ADMIN_KEY\"}'"
echo ""
echo "Test guest access:"
echo "  curl -X POST http://localhost:8000/auth/guest"
echo ""
echo "Test login:"
echo "  curl -X POST http://localhost:8000/auth/login -H 'Content-Type: application/json' -d '{\"email\":\"sanam.ctaula@gmail.com\",\"password\":\"YOUR_PASSWORD\"}'"
