import httpx
"""
FastAPI Backend — REST API for all AI agents + model management
"""
import os
import json
import time
import secrets
from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any

from agents.shared.database import query, execute
from agents.shared.model_manager import (
    ollama_list, ollama_pull, ollama_delete, ollama_model_info,
    add_paid_model, remove_model, list_registered_models,
    set_default_model, get_default_model, get_model_config, PROVIDERS,
    ensure_model_table, seed_defaults,
)
from agents.restaurant.agent import create_restaurant_agent
from agents.real_estate.agent import create_real_estate_agent
from agents.social_media.agent import create_social_media_agent
from agents.marketing.agent import create_marketing_agent
from agents.video.agent import create_video_agent

app = FastAPI(
    title="Maicha AI Platform",
    description="REST API for AI agents + dynamic model management",
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


# ── Agent instances ──
agents = {}

def get_agent(agent_type: str):
    if agent_type not in agents:
        factories = {
            "restaurant": create_restaurant_agent,
            "real-estate": create_real_estate_agent,
            "social-media": create_social_media_agent,
            "marketing": create_marketing_agent,
            "video": create_video_agent,
        }
        if agent_type not in factories:
            raise HTTPException(status_code=404, detail=f"Unknown agent: {agent_type}")
        agents[agent_type] = factories[agent_type]()
    return agents[agent_type]


# ── Auth ──
API_KEY = os.getenv("API_KEY", "change-me-to-a-real-key")

def verify_api_key(x_api_key: str = Header(None)):
    if API_KEY == "change-me-to-a-real-key":
        return True
    if not x_api_key or x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return True


# ── Request/Response Models ──
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


# ── Core routes ──

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
    return {"status": "healthy", "database": db_status, "agents": list(agents.keys())}

@app.get("/agents")
def list_agents():
    return {"agents": [
        {"name": "restaurant", "description": "Food orders, menu, reservations"},
        {"name": "real-estate", "description": "Property listings, inquiries, lead qualification"},
        {"name": "social-media", "description": "Content creation, hashtags, scheduling"},
        {"name": "marketing", "description": "Ad copy, emails, blog posts, campaigns"},
        {"name": "video", "description": "Video scripts, media production"},
    ]}


@app.post("/chat", response_model=ChatResponse)
def chat_endpoint(req: ChatRequest, auth: bool = Depends(verify_api_key)):
    start = time.time()
    agent = get_agent(req.agent_type)

    model_name = req.model or os.getenv("DEFAULT_MODEL", "llama3.2:3b")

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
        response=response,
        agent_type=req.agent_type,
        model_used=model_name,
        session_id=session_id,
        elapsed_seconds=elapsed,
    )


# ── Model Management Routes ──

@app.get("/models")
def get_models():
    """List all registered models (local + paid)."""
    registered = list_registered_models()
    ollama_models = ollama_list()
    return {
        "registered": registered,
        "ollama_installed": ollama_models if not isinstance(ollama_models, dict) else [],
        "providers": {k: {"label": v["label"], "default_models": v["default_models"]} for k, v in PROVIDERS.items()},
        "default": get_default_model(),
    }

@app.get("/models/ollama")
def get_ollama_models():
    """List models installed in Ollama."""
    return {"models": ollama_list()}

@app.post("/models/ollama/pull")
def pull_ollama_model(req: PullModelRequest):
    """Pull a new model from Ollama registry."""
    return ollama_pull(req.name)

@app.delete("/models/ollama/{model_name}")
def delete_ollama_model(model_name: str):
    """Delete an Ollama model."""
    return ollama_delete(model_name)

@app.get("/models/ollama/{model_name}/info")
def get_model_info(model_name: str):
    """Get details about an installed Ollama model."""
    return ollama_model_info(model_name)

@app.post("/models/paid")
def add_paid_api_model(req: AddPaidModelRequest):
    """Register a paid API model (OpenAI, Anthropic, DeepSeek, Kimi)."""
    return add_paid_model(req.name, req.provider, req.model_id, req.api_key, req.api_base_url)

@app.delete("/models/{model_name}")
def delete_model(model_name: str):
    """Remove a model from the registry."""
    return remove_model(model_name)

@app.post("/models/default")
def set_default(req: SetDefaultRequest):
    """Set the default model."""
    return set_default_model(req.name)

@app.get("/models/providers")
def get_providers():
    """List available model providers and their default models."""
    return {"providers": {k: {"label": v["label"], "default_models": v["default_models"]} for k, v in PROVIDERS.items()}}


# ── Data routes ──

@app.get("/menu")
def get_menu(category: Optional[str] = None):
    if category:
        items = query(
            "SELECT name, description, category, price, dietary_tags FROM menu_items "
            "WHERE is_available = true AND LOWER(category) = LOWER(%s) ORDER BY category, name", (category,))
    else:
        items = query(
            "SELECT name, description, category, price, dietary_tags FROM menu_items "
            "WHERE is_available = true ORDER BY category, name")
    return {"menu_items": items, "count": len(items)}

@app.get("/properties")
def get_properties(city: Optional[str] = None, listing_type: Optional[str] = None):
    conditions = ["status = 'active'"]
    params = []
    if city:
        conditions.append("LOWER(city) = LOWER(%s)")
        params.append(city)
    if listing_type:
        conditions.append("LOWER(listing_type) = LOWER(%s)")
        params.append(listing_type)
    where = " AND ".join(conditions)
    props = query(
        f"SELECT title, description, property_type, listing_type, price, bedrooms, bathrooms, city, state "
        f"FROM property_listings WHERE {where} ORDER BY created_at DESC LIMIT 20",
        tuple(params) if params else None)
    return {"properties": props, "count": len(props)}

@app.get("/orders")
def get_orders(status: Optional[str] = None, limit: int = 20):
    if status:
        orders = query(
            "SELECT id, customer_name, status, total, created_at FROM orders "
            "WHERE LOWER(status) = LOWER(%s) ORDER BY created_at DESC LIMIT %s", (status, limit))
    else:
        orders = query("SELECT id, customer_name, status, total, created_at FROM orders ORDER BY created_at DESC LIMIT %s", (limit,))
    return {"orders": orders, "count": len(orders)}

@app.get("/conversations")
def get_conversations(agent_type: Optional[str] = None, limit: int = 20):
    if agent_type:
        convos = query(
            "SELECT id, agent_type, title, status, created_at FROM conversations "
            "WHERE agent_type = %s ORDER BY created_at DESC LIMIT %s", (agent_type, limit))
    else:
        convos = query("SELECT id, agent_type, title, status, created_at FROM conversations ORDER BY created_at DESC LIMIT %s", (limit,))
    return {"conversations": convos, "count": len(convos)}

@app.get("/events")
def get_events(source: Optional[str] = None, limit: int = 50):
    if source:
        events = query(
            "SELECT event_type, source, data, created_at FROM events "
            "WHERE source = %s ORDER BY created_at DESC LIMIT %s", (source, limit))
    else:
        events = query("SELECT event_type, source, data, created_at FROM events ORDER BY created_at DESC LIMIT %s", (limit,))
    return {"events": events, "count": len(events)}

@app.get("/stats")
def get_stats():
    stats = {}
    for table in ["conversations", "messages", "orders", "reservations", "property_listings",
                   "property_inquiries", "content_queue", "generated_scripts", "media_jobs", "events"]:
        result = query(f"SELECT count(*) as count FROM {table}")
        stats[table] = result[0]["count"]
    return {"stats": stats}


# ── n8n Integration Routes ──

@app.get("/n8n/workflows")
def list_n8n_workflows():
    """List available n8n workflow templates."""
    import glob
    workflows = []
    for f in sorted(glob.glob("/app/agents/../n8n/workflows/*.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
                workflows.append({
                    "file": f.split("/")[-1],
                    "name": data.get("name", "Unknown"),
                    "description": data.get("description", ""),
                })
        except Exception:
            pass

    # Also try the mounted path
    for f in sorted(glob.glob("/opt/ai-server/n8n/workflows/*.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
                name = data.get("name", "Unknown")
                if not any(w["name"] == name for w in workflows):
                    workflows.append({
                        "file": f.split("/")[-1],
                        "name": name,
                        "description": data.get("description", ""),
                    })
        except Exception:
            pass

    return {
        "workflows": workflows,
        "n8n_url": "http://20.41.122.188:5678",
        "n8n_status": _check_n8n_status(),
    }


def _check_n8n_status():
    """Check if n8n is reachable."""
    try:
        resp = httpx.get("http://n8n:5678/healthz", timeout=3.0)
        return "running" if resp.status_code == 200 else "error"
    except Exception:
        return "unreachable"


@app.get("/n8n/workflow/{filename}")
def get_n8n_workflow(filename: str):
    """Get a specific workflow template."""
    import os.path
    for base_path in ["/opt/ai-server/n8n/workflows", "/app/agents/../n8n/workflows"]:
        filepath = os.path.join(base_path, filename)
        if os.path.exists(filepath):
            with open(filepath) as f:
                return json.load(f)
    raise HTTPException(status_code=404, detail=f"Workflow not found: {filename}")


# ── Settings Routes ──

from agents.shared.settings_manager import (
    get_all_settings, get_category_settings, set_setting,
    save_smtp_config, save_telegram_config, save_slack_config, save_discord_config,
    test_smtp, test_telegram, test_slack, test_discord,
    ensure_settings_table,
)


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

class SettingRequest(BaseModel):
    category: str
    key: str
    value: str
    is_secret: bool = False


@app.get("/settings")
def get_settings():
    """Get all platform settings (secrets masked)."""
    ensure_settings_table()
    return {
        "settings": get_all_settings(mask_secrets=True),
        "categories": {
            "smtp": {"label": "Email (SMTP)", "description": "Send emails via SMTP server"},
            "telegram": {"label": "Telegram", "description": "Send notifications via Telegram bot"},
            "slack": {"label": "Slack", "description": "Send notifications via Slack webhook"},
            "discord": {"label": "Discord", "description": "Send notifications via Discord webhook"},
            "whatsapp": {"label": "WhatsApp", "description": "Send messages via WhatsApp Business API"},
            "general": {"label": "General", "description": "Platform-wide settings"},
        }
    }

@app.get("/settings/{category}")
def get_settings_by_category(category: str):
    """Get settings for a specific category."""
    return {"category": category, "settings": get_category_settings(category)}

@app.post("/settings")
def save_setting(req: SettingRequest):
    """Save a single setting."""
    set_setting(req.category, req.key, req.value, req.is_secret)
    return {"status": "saved", "category": req.category, "key": req.key}

@app.post("/settings/smtp")
def configure_smtp(req: SmtpConfigRequest):
    """Configure SMTP email settings."""
    return save_smtp_config(req.host, req.port, req.username, req.password, req.from_email, req.use_tls)

@app.post("/settings/telegram")
def configure_telegram(req: TelegramConfigRequest):
    """Configure Telegram bot."""
    return save_telegram_config(req.bot_token, req.default_chat_id)

@app.post("/settings/slack")
def configure_slack(req: SlackConfigRequest):
    """Configure Slack webhook."""
    return save_slack_config(req.webhook_url, req.default_channel)

@app.post("/settings/discord")
def configure_discord(req: DiscordConfigRequest):
    """Configure Discord webhook."""
    return save_discord_config(req.webhook_url)

@app.post("/settings/smtp/test")
def test_smtp_connection():
    """Test SMTP connection."""
    return test_smtp()

@app.post("/settings/telegram/test")
def test_telegram_connection():
    """Test Telegram bot."""
    return test_telegram()

@app.post("/settings/slack/test")
def test_slack_connection():
    """Test Slack webhook (sends a test message)."""
    return test_slack()

@app.post("/settings/discord/test")
def test_discord_connection():
    """Test Discord webhook (sends a test message)."""
    return test_discord()


# ── Notification Routes ──

from agents.shared.notification_sender import send_email, send_telegram, send_slack, send_discord, send_notification


class SendEmailRequest(BaseModel):
    to_email: str
    subject: str
    body: str
    html_body: Optional[str] = None

class SendNotificationRequest(BaseModel):
    message: str
    channels: Optional[List[str]] = None


@app.post("/notify/email")
def api_send_email(req: SendEmailRequest):
    """Send an email via configured SMTP."""
    return send_email(req.to_email, req.subject, req.body, req.html_body)

@app.post("/notify/telegram")
def api_send_telegram(req: SendNotificationRequest):
    """Send a Telegram message."""
    return send_telegram(req.message)

@app.post("/notify/slack")
def api_send_slack(req: SendNotificationRequest):
    """Send a Slack message."""
    return send_slack(req.message)

@app.post("/notify/discord")
def api_send_discord(req: SendNotificationRequest):
    """Send a Discord message."""
    return send_discord(req.message)

@app.post("/notify/all")
def api_send_all(req: SendNotificationRequest):
    """Send notification to all configured channels."""
    return send_notification(req.message, req.channels)


# ── WhatsApp Routes ──

from agents.shared.settings_manager import save_whatsapp_config, test_whatsapp
from agents.shared.notification_sender import send_whatsapp


class WhatsAppConfigRequest(BaseModel):
    phone_number_id: str
    access_token: str
    verify_token: Optional[str] = None

class SendWhatsAppRequest(BaseModel):
    to_phone: str
    message: str


@app.post("/settings/whatsapp")
def configure_whatsapp(req: WhatsAppConfigRequest):
    """Configure WhatsApp Business API."""
    return save_whatsapp_config(req.phone_number_id, req.access_token, req.verify_token)

@app.post("/settings/whatsapp/test")
def test_whatsapp_connection():
    """Test WhatsApp Business API connection."""
    return test_whatsapp()

@app.post("/notify/whatsapp")
def api_send_whatsapp(req: SendWhatsAppRequest):
    """Send a WhatsApp message."""
    return send_whatsapp(req.to_phone, req.message)
