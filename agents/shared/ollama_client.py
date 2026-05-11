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
