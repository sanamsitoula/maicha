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
    """Pull a model from Ollama registry."""
    try:
        # First check if model already exists
        existing = ollama_list()
        if not isinstance(existing, dict):
            for m in existing:
                if m.get("name") == model_name:
                    ensure_model_table()
                    execute(
                        "INSERT INTO model_registry (name, provider, model_id) "
                        "VALUES (%s, 'ollama', %s) ON CONFLICT (name) DO UPDATE SET is_active = true",
                        (model_name, model_name)
                    )
                    return {"status": "success", "model": model_name, "message": "Model already installed"}

        # Pull with streaming disabled — long timeout for large models
        resp = httpx.post(
            f"{OLLAMA_BASE_URL}/api/pull",
            json={"name": model_name, "stream": False},
            timeout=1800.0,
        )
        if resp.status_code == 200:
            ensure_model_table()
            execute(
                "INSERT INTO model_registry (name, provider, model_id) "
                "VALUES (%s, 'ollama', %s) ON CONFLICT (name) DO UPDATE SET is_active = true",
                (model_name, model_name)
            )
            return {"status": "success", "model": model_name}
        else:
            return {"status": "error", "error": f"Ollama returned {resp.status_code}: {resp.text[:200]}"}
    except httpx.TimeoutException:
        return {"status": "pulling", "model": model_name, "message": "Model is downloading (large file). Check GET /models/ollama in a few minutes."}
    except httpx.ConnectError:
        return {"status": "error", "error": "Cannot connect to Ollama. Is the ai-ollama container running?"}
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
