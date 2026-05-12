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
    """Telegram bot webhook — handles multi-step food ordering."""
    from agents.shared.telegram_bot import process_telegram_message

    body = await request.json()
    message = body.get("message", {})
    text = message.get("text", "")
    chat_id = str(message.get("chat", {}).get("id", ""))
    user_name = message.get("from", {}).get("first_name", "Customer")

    if not text or not chat_id:
        return {"ok": True}

    reply = process_telegram_message(chat_id, user_name, text)
    send_telegram(reply, chat_id)
    return {"ok": True}


@app.post("/webhook/telegram/register")
async def register_telegram_webhook():
    """Register the Telegram webhook URL with Telegram API."""
    from agents.shared.settings_manager import get_setting
    from agents.shared.database import query as db_query

    token_result = db_query("SELECT value FROM platform_settings WHERE category = 'telegram' AND key = 'bot_token'")
    if not token_result:
        return {"status": "error", "message": "Telegram bot token not configured. Go to Settings > Telegram first."}

    token = token_result[0]["value"]
    webhook_url = f"http://20.41.122.188/webhook/telegram"

    resp = httpx.post(
        f"https://api.telegram.org/bot{token}/setWebhook",
        json={"url": webhook_url},
        timeout=10.0,
    )
    data = resp.json()

    if data.get("ok"):
        return {"status": "ok", "message": "Webhook registered!", "url": webhook_url}
    return {"status": "error", "message": data.get("description", "Unknown error")}


@app.get("/webhook/telegram/info")
async def telegram_webhook_info():
    """Check current Telegram webhook status."""
    from agents.shared.database import query as db_query

    token_result = db_query("SELECT value FROM platform_settings WHERE category = 'telegram' AND key = 'bot_token'")
    if not token_result:
        return {"status": "error", "message": "Telegram not configured"}

    token = token_result[0]["value"]
    resp = httpx.get(f"https://api.telegram.org/bot{token}/getWebhookInfo", timeout=10.0)
    return resp.json()


# ══════════════════════════════════════════
# CRUD: MENU ITEMS
# ══════════════════════════════════════════

class AddMenuItemRequest(BaseModel):
    name: str
    description: str = ""
    category: str = "main"
    price: float
    dietary_tags: Optional[List[str]] = []
    is_available: bool = True

class UpdateMenuItemRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    dietary_tags: Optional[List[str]] = None
    is_available: Optional[bool] = None


@app.post("/menu/add", dependencies=[Depends(require_admin)])
def add_menu_item(req: AddMenuItemRequest):
    """Add a new menu item (admin only)."""
    restaurants = query("SELECT id FROM restaurants LIMIT 1")
    if not restaurants:
        return {"status": "error", "message": "No restaurant configured. Create one first."}
    result = execute(
        "INSERT INTO menu_items (restaurant_id, name, description, category, price, dietary_tags, is_available) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id, name, price",
        (restaurants[0]["id"], req.name, req.description, req.category, req.price,
         json.dumps(req.dietary_tags or []), req.is_available)
    )
    return {"status": "added", "item": result[0] if result else None}


@app.put("/menu/{item_name}", dependencies=[Depends(require_admin)])
def update_menu_item(item_name: str, req: UpdateMenuItemRequest):
    """Update a menu item by name (admin only)."""
    updates = []
    params = []
    if req.name is not None:
        updates.append("name = %s")
        params.append(req.name)
    if req.description is not None:
        updates.append("description = %s")
        params.append(req.description)
    if req.category is not None:
        updates.append("category = %s")
        params.append(req.category)
    if req.price is not None:
        updates.append("price = %s")
        params.append(req.price)
    if req.dietary_tags is not None:
        updates.append("dietary_tags = %s")
        params.append(json.dumps(req.dietary_tags))
    if req.is_available is not None:
        updates.append("is_available = %s")
        params.append(req.is_available)
    if not updates:
        return {"status": "error", "message": "Nothing to update"}
    updates.append("updated_at = CURRENT_TIMESTAMP")
    params.append(item_name)
    execute(f"UPDATE menu_items SET {', '.join(updates)} WHERE LOWER(name) = LOWER(%s)", tuple(params))
    return {"status": "updated", "item": item_name}


@app.delete("/menu/{item_name}", dependencies=[Depends(require_admin)])
def delete_menu_item(item_name: str):
    """Delete a menu item by name (admin only)."""
    execute("DELETE FROM menu_items WHERE LOWER(name) = LOWER(%s)", (item_name,))
    return {"status": "deleted", "item": item_name}


# ══════════════════════════════════════════
# CRUD: PROPERTY LISTINGS
# ══════════════════════════════════════════

class AddPropertyRequest(BaseModel):
    title: str
    description: str = ""
    property_type: str = "apartment"
    listing_type: str = "rent"
    price: float
    bedrooms: Optional[int] = None
    bathrooms: Optional[float] = None
    area_sqft: Optional[float] = None
    city: str = ""
    state: str = ""
    zip_code: str = ""
    address_line1: str = ""
    features: Optional[List[str]] = []


@app.post("/properties/add", dependencies=[Depends(require_admin)])
def add_property(req: AddPropertyRequest):
    """Add a new property listing (admin only)."""
    result = execute(
        "INSERT INTO property_listings (title, description, property_type, listing_type, price, "
        "bedrooms, bathrooms, area_sqft, city, state, zip_code, address_line1, features, status) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'active') RETURNING id, title, price",
        (req.title, req.description, req.property_type, req.listing_type, req.price,
         req.bedrooms, req.bathrooms, req.area_sqft, req.city, req.state, req.zip_code,
         req.address_line1, json.dumps(req.features or []))
    )
    return {"status": "added", "property": result[0] if result else None}


@app.delete("/properties/{property_id}", dependencies=[Depends(require_admin)])
def delete_property(property_id: str):
    """Delete a property listing (admin only)."""
    execute("UPDATE property_listings SET status = 'archived' WHERE id = %s::uuid", (property_id,))
    return {"status": "archived", "id": property_id}


# ══════════════════════════════════════════
# DETAILED: ORDERS + CONVERSATIONS
# ══════════════════════════════════════════

@app.get("/orders/{order_id}")
def get_order_detail(order_id: str):
    """Get full order details with items, customer info."""
    order = query(
        "SELECT o.id, o.customer_name, o.customer_email, o.customer_phone, "
        "o.order_type, o.status, o.subtotal, o.tax, o.total, "
        "o.special_instructions, o.created_at, o.updated_at "
        "FROM orders o WHERE o.id = %s::uuid", (order_id,))
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    order = order[0]
    items = query(
        "SELECT oi.quantity, oi.unit_price, oi.total_price, oi.special_requests, mi.name, mi.category "
        "FROM order_items oi JOIN menu_items mi ON oi.menu_item_id = mi.id "
        "WHERE oi.order_id = %s::uuid", (order_id,))
    order["items"] = items
    return {"order": order}


@app.get("/orders-detailed")
def get_orders_detailed(status: Optional[str] = None, limit: int = 20):
    """Get orders with full details including items and customer info."""
    if status:
        orders = query(
            "SELECT o.id, o.customer_name, o.customer_phone, o.status, o.total, "
            "o.special_instructions, o.order_type, o.created_at "
            "FROM orders o WHERE LOWER(o.status) = LOWER(%s) "
            "ORDER BY o.created_at DESC LIMIT %s", (status, limit))
    else:
        orders = query(
            "SELECT o.id, o.customer_name, o.customer_phone, o.status, o.total, "
            "o.special_instructions, o.order_type, o.created_at "
            "FROM orders o ORDER BY o.created_at DESC LIMIT %s", (limit,))
    for order in orders:
        items = query(
            "SELECT mi.name, oi.quantity, oi.total_price "
            "FROM order_items oi JOIN menu_items mi ON oi.menu_item_id = mi.id "
            "WHERE oi.order_id = %s::uuid", (str(order["id"]),))
        order["items"] = items
    return {"orders": orders, "count": len(orders)}


@app.get("/conversations/{conv_id}/messages")
def get_conversation_messages(conv_id: str, limit: int = 50):
    """Get all messages in a conversation."""
    conv = query(
        "SELECT id, agent_type, title, status, created_at FROM conversations WHERE id = %s::uuid",
        (conv_id,))
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    messages = query(
        "SELECT role, content, model_used, created_at FROM messages "
        "WHERE conversation_id = %s::uuid ORDER BY created_at ASC LIMIT %s",
        (conv_id, limit))
    return {"conversation": conv[0], "messages": messages, "count": len(messages)}


@app.get("/conversations-detailed")
def get_conversations_detailed(agent_type: Optional[str] = None, limit: int = 20):
    """Get conversations with message count and last message preview."""
    if agent_type:
        convos = query(
            "SELECT c.id, c.agent_type, c.title, c.status, c.created_at, "
            "COUNT(m.id) as message_count, "
            "MAX(m.created_at) as last_message_at "
            "FROM conversations c LEFT JOIN messages m ON c.id = m.conversation_id "
            "WHERE c.agent_type = %s "
            "GROUP BY c.id ORDER BY c.created_at DESC LIMIT %s",
            (agent_type, limit))
    else:
        convos = query(
            "SELECT c.id, c.agent_type, c.title, c.status, c.created_at, "
            "COUNT(m.id) as message_count, "
            "MAX(m.created_at) as last_message_at "
            "FROM conversations c LEFT JOIN messages m ON c.id = m.conversation_id "
            "GROUP BY c.id ORDER BY c.created_at DESC LIMIT %s",
            (limit,))
    # Get last message preview for each
    for c in convos:
        last_msg = query(
            "SELECT role, LEFT(content, 100) as preview FROM messages "
            "WHERE conversation_id = %s::uuid ORDER BY created_at DESC LIMIT 1",
            (str(c["id"]),))
        c["last_message"] = last_msg[0] if last_msg else None
    return {"conversations": convos, "count": len(convos)}


@app.get("/reservations")
def get_reservations(limit: int = 20):
    """Get all reservations with details."""
    return {"reservations": query(
        "SELECT id, customer_name, customer_phone, party_size, "
        "reservation_date, reservation_time, status, special_requests, created_at "
        "FROM reservations ORDER BY reservation_date DESC, reservation_time DESC LIMIT %s",
        (limit,))}


# ══════════════════════════════════════════
# CRUD: RESTAURANTS
# ══════════════════════════════════════════

class AddRestaurantRequest(BaseModel):
    name: str
    description: str = ""
    cuisine_type: str = ""
    address: str = ""
    phone: str = ""


@app.post("/restaurants/add", dependencies=[Depends(require_admin)])
def add_restaurant(req: AddRestaurantRequest):
    """Add a new restaurant (admin only)."""
    result = execute(
        "INSERT INTO restaurants (name, description, cuisine_type, address, phone) "
        "VALUES (%s, %s, %s, %s, %s) RETURNING id, name",
        (req.name, req.description, req.cuisine_type, req.address, req.phone))
    return {"status": "added", "restaurant": result[0] if result else None}


@app.put("/orders/{order_id}/status", dependencies=[Depends(require_admin)])
def update_order_status(order_id: str, status: str):
    """Update order status (admin only)."""
    valid = ["pending", "confirmed", "preparing", "ready", "delivered", "cancelled"]
    if status not in valid:
        return {"status": "error", "message": f"Invalid status. Use: {', '.join(valid)}"}
    execute("UPDATE orders SET status = %s, updated_at = CURRENT_TIMESTAMP WHERE id = %s::uuid",
            (status, order_id))
    return {"status": "updated", "order_id": order_id, "new_status": status}
