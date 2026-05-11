#!/bin/bash
set -e
echo "=== Phase 2: Dynamic Model Management ==="

AGENTS="/opt/ai-server/agents"

# ============================================
# 1. Create model_manager.py — handles Ollama + paid APIs
# ============================================
cat > "$AGENTS/shared/model_manager.py" << 'EOF'
"""
Model Manager — dynamic model registry supporting:
- Ollama local models (pull, list, delete)
- Paid APIs (OpenAI, Anthropic, DeepSeek, Kimi)
"""
import os
import json
import httpx
from agents.shared.database import query, execute

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")


# ── Database table for model configs ──

def ensure_model_table():
    """Create the model registry table if it doesn't exist."""
    execute("""
        CREATE TABLE IF NOT EXISTS model_registry (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255) UNIQUE NOT NULL,
            provider VARCHAR(50) NOT NULL,
            model_id VARCHAR(255) NOT NULL,
            api_base_url VARCHAR(500),
            api_key_encrypted TEXT,
            is_active BOOLEAN DEFAULT true,
            is_default BOOLEAN DEFAULT false,
            config JSONB DEFAULT '{}',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)


def seed_defaults():
    """Add default Ollama models if table is empty."""
    ensure_model_table()
    existing = query("SELECT COUNT(*) as c FROM model_registry")
    if existing[0]["c"] == 0:
        defaults = [
            ("llama3.2:3b", "ollama", "llama3.2:3b", True),
            ("phi3:mini", "ollama", "phi3:mini", False),
        ]
        for name, provider, model_id, is_default in defaults:
            execute(
                "INSERT INTO model_registry (name, provider, model_id, is_default) "
                "VALUES (%s, %s, %s, %s) ON CONFLICT (name) DO NOTHING",
                (name, provider, model_id, is_default)
            )


# ── Ollama operations ──

def ollama_list():
    """List models installed in Ollama."""
    try:
        resp = httpx.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=10.0)
        resp.raise_for_status()
        return resp.json().get("models", [])
    except Exception as e:
        return {"error": str(e)}


def ollama_pull(model_name):
    """Pull a model from Ollama registry. Returns stream progress."""
    try:
        resp = httpx.post(
            f"{OLLAMA_BASE_URL}/api/pull",
            json={"name": model_name, "stream": False},
            timeout=600.0,
        )
        resp.raise_for_status()
        ensure_model_table()
        execute(
            "INSERT INTO model_registry (name, provider, model_id) "
            "VALUES (%s, 'ollama', %s) ON CONFLICT (name) DO UPDATE SET is_active = true",
            (model_name, model_name)
        )
        return {"status": "success", "model": model_name}
    except httpx.TimeoutException:
        return {"status": "pulling", "model": model_name, "message": "Model is downloading. This can take several minutes. Check /models/ollama to see when it appears."}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def ollama_delete(model_name):
    """Delete a model from Ollama."""
    try:
        resp = httpx.request(
            "DELETE",
            f"{OLLAMA_BASE_URL}/api/delete",
            json={"name": model_name},
            timeout=30.0,
        )
        resp.raise_for_status()
        execute(
            "UPDATE model_registry SET is_active = false WHERE name = %s AND provider = 'ollama'",
            (model_name,)
        )
        return {"status": "deleted", "model": model_name}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def ollama_model_info(model_name):
    """Get details about an installed Ollama model."""
    try:
        resp = httpx.post(
            f"{OLLAMA_BASE_URL}/api/show",
            json={"name": model_name},
            timeout=10.0,
        )
        resp.raise_for_status()
        data = resp.json()
        return {
            "name": model_name,
            "family": data.get("details", {}).get("family", "unknown"),
            "parameter_size": data.get("details", {}).get("parameter_size", "unknown"),
            "quantization": data.get("details", {}).get("quantization_level", "unknown"),
            "format": data.get("details", {}).get("format", "unknown"),
        }
    except Exception as e:
        return {"error": str(e)}


# ── Paid API providers ──

PROVIDERS = {
    "openai": {
        "label": "OpenAI",
        "base_url": "https://api.openai.com/v1",
        "default_models": ["gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo"],
    },
    "anthropic": {
        "label": "Anthropic",
        "base_url": "https://api.anthropic.com",
        "default_models": ["claude-sonnet-4-20250514", "claude-haiku-4-5-20251001"],
    },
    "deepseek": {
        "label": "DeepSeek",
        "base_url": "https://api.deepseek.com/v1",
        "default_models": ["deepseek-chat", "deepseek-coder"],
    },
    "kimi": {
        "label": "Kimi (Moonshot)",
        "base_url": "https://api.moonshot.cn/v1",
        "default_models": ["moonshot-v1-8k", "moonshot-v1-32k"],
    },
    "ollama": {
        "label": "Ollama (Local)",
        "base_url": OLLAMA_BASE_URL,
        "default_models": [],
    },
}


def add_paid_model(name, provider, model_id, api_key, api_base_url=None):
    """Register a paid API model."""
    if provider not in PROVIDERS:
        return {"error": f"Unknown provider: {provider}. Available: {', '.join(PROVIDERS.keys())}"}
    ensure_model_table()
    base_url = api_base_url or PROVIDERS[provider]["base_url"]
    execute(
        "INSERT INTO model_registry (name, provider, model_id, api_base_url, api_key_encrypted, is_active) "
        "VALUES (%s, %s, %s, %s, %s, true) "
        "ON CONFLICT (name) DO UPDATE SET provider = %s, model_id = %s, api_base_url = %s, api_key_encrypted = %s, is_active = true",
        (name, provider, model_id, base_url, api_key, provider, model_id, base_url, api_key)
    )
    return {"status": "added", "name": name, "provider": provider, "model_id": model_id}


def remove_model(name):
    """Remove a model from the registry."""
    execute("DELETE FROM model_registry WHERE name = %s", (name,))
    return {"status": "removed", "name": name}


def list_registered_models():
    """List all models in the registry."""
    ensure_model_table()
    seed_defaults()
    models = query(
        "SELECT name, provider, model_id, api_base_url, is_active, is_default, config, created_at "
        "FROM model_registry ORDER BY provider, name"
    )
    return models


def set_default_model(name):
    """Set a model as the default."""
    ensure_model_table()
    execute("UPDATE model_registry SET is_default = false WHERE is_default = true")
    execute("UPDATE model_registry SET is_default = true WHERE name = %s", (name,))
    return {"status": "ok", "default": name}


def get_default_model():
    """Get the current default model."""
    ensure_model_table()
    seed_defaults()
    result = query("SELECT name, provider, model_id, api_base_url, api_key_encrypted FROM model_registry WHERE is_default = true LIMIT 1")
    if result:
        return result[0]
    return {"name": "llama3.2:3b", "provider": "ollama", "model_id": "llama3.2:3b"}


def get_model_config(name):
    """Get full config for a specific model."""
    result = query(
        "SELECT name, provider, model_id, api_base_url, api_key_encrypted, config "
        "FROM model_registry WHERE name = %s AND is_active = true",
        (name,)
    )
    if result:
        return result[0]
    return None
EOF

echo "Created model_manager.py"

# ============================================
# 2. Update ollama_client.py — support paid APIs
# ============================================
cat > "$AGENTS/shared/ollama_client.py" << 'EOF'
"""
Unified LLM client — routes to Ollama or paid APIs based on model config.
"""
import httpx
import json
import os

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
DEFAULT_MODEL = os.getenv("DEFAULT_MODEL", "llama3.2:3b")


def _call_ollama(messages, model, temperature):
    """Call local Ollama API."""
    response = httpx.post(
        f"{OLLAMA_BASE_URL}/api/chat",
        json={
            "model": model,
            "messages": messages,
            "stream": False,
            "options": {"temperature": temperature},
        },
        timeout=300.0,
    )
    response.raise_for_status()
    return response.json()["message"]["content"]


def _call_openai_compatible(messages, model_id, api_key, base_url, temperature):
    """Call OpenAI-compatible API (works for OpenAI, DeepSeek, Kimi)."""
    response = httpx.post(
        f"{base_url}/chat/completions",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": model_id,
            "messages": messages,
            "temperature": temperature,
        },
        timeout=120.0,
    )
    response.raise_for_status()
    return response.json()["choices"][0]["message"]["content"]


def _call_anthropic(messages, model_id, api_key, base_url, temperature):
    """Call Anthropic API."""
    system_msg = None
    chat_messages = []
    for m in messages:
        if m["role"] == "system":
            system_msg = m["content"]
        else:
            chat_messages.append(m)

    body = {
        "model": model_id,
        "max_tokens": 4096,
        "messages": chat_messages,
        "temperature": temperature,
    }
    if system_msg:
        body["system"] = system_msg

    response = httpx.post(
        f"{base_url}/v1/messages",
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        json=body,
        timeout=120.0,
    )
    response.raise_for_status()
    data = response.json()
    return data["content"][0]["text"]


def chat(messages, model=None, temperature=0.7, model_config=None):
    """
    Send messages to the appropriate LLM.

    Args:
        messages: list of {"role": "...", "content": "..."}
        model: model name (looks up config from DB if model_config not provided)
        temperature: creativity level
        model_config: optional pre-fetched config dict with provider, model_id, api_key_encrypted, api_base_url
    """
    model = model or DEFAULT_MODEL

    if model_config is None:
        try:
            from agents.shared.model_manager import get_model_config
            model_config = get_model_config(model)
        except Exception:
            model_config = None

    if model_config and model_config.get("provider") not in (None, "ollama"):
        provider = model_config["provider"]
        api_key = model_config.get("api_key_encrypted", "")
        base_url = model_config.get("api_base_url", "")
        model_id = model_config.get("model_id", model)

        if provider == "anthropic":
            return _call_anthropic(messages, model_id, api_key, base_url, temperature)
        else:
            return _call_openai_compatible(messages, model_id, api_key, base_url, temperature)
    else:
        return _call_ollama(messages, model, temperature)


def generate(prompt, model=None, temperature=0.7, system=None):
    """Simple one-shot generation."""
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    return chat(messages, model=model, temperature=temperature)
EOF

echo "Updated ollama_client.py"

# ============================================
# 3. Update api.py — add model management endpoints
# ============================================
cat > "$AGENTS/api.py" << 'EOF'
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
EOF

echo "Updated api.py with model management endpoints"

# ============================================
# 4. Git commit
# ============================================
cd /opt/ai-server
git add agents/shared/model_manager.py
git add agents/shared/ollama_client.py
git add agents/api.py

git commit -m "Phase 2: Dynamic model management

- model_manager.py: Ollama pull/delete/list, paid API registry (OpenAI, Anthropic, DeepSeek, Kimi)
- ollama_client.py: unified LLM client routing to local or paid APIs
- api.py: /models endpoints for managing models from UI
- model_registry table auto-created on startup
- Chat endpoint now accepts optional model parameter"

echo ""
echo "=== Phase 2 deployed ==="
echo ""
echo "Run:"
echo "  cd /opt/ai-server"
echo "  docker compose build fastapi agent-runner"
echo "  docker compose up -d"
echo "  git push"
echo ""
echo "Test:"
echo "  curl http://localhost:8000/models"
echo "  curl http://localhost:8000/models/providers"
echo "  curl http://localhost:8000/models/ollama"
echo "  curl -X POST http://localhost:8000/models/ollama/pull -H 'Content-Type: application/json' -d '{\"name\":\"qwen3:0.6b\"}'"
echo "  curl -X POST http://localhost:8000/models/default -H 'Content-Type: application/json' -d '{\"name\":\"llama3.2:3b\"}'"
