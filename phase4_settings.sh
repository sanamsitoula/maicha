#!/bin/bash
set -e
echo "=== Phase 4: Settings Panel (SMTP, Telegram, Slack, Discord) ==="

BASE="/opt/ai-server"
AGENTS="$BASE/agents"
cd "$BASE"

# ============================================
# Step 1: Create settings_manager.py
# ============================================
cat > "$AGENTS/shared/settings_manager.py" << 'EOF'
"""
Settings Manager — stores and retrieves admin configuration:
- SMTP (email sending)
- Telegram bot
- Slack webhook
- Discord webhook
- General platform settings
"""
import json
from agents.shared.database import query, execute


def ensure_settings_table():
    """Create settings table if it doesn't exist."""
    execute("""
        CREATE TABLE IF NOT EXISTS platform_settings (
            id SERIAL PRIMARY KEY,
            category VARCHAR(50) NOT NULL,
            key VARCHAR(100) NOT NULL,
            value TEXT,
            is_secret BOOLEAN DEFAULT false,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(category, key)
        )
    """)


def get_setting(category, key):
    """Get a single setting value."""
    ensure_settings_table()
    result = query(
        "SELECT value FROM platform_settings WHERE category = %s AND key = %s",
        (category, key)
    )
    return result[0]["value"] if result else None


def set_setting(category, key, value, is_secret=False):
    """Set a single setting value."""
    ensure_settings_table()
    execute(
        "INSERT INTO platform_settings (category, key, value, is_secret, updated_at) "
        "VALUES (%s, %s, %s, %s, CURRENT_TIMESTAMP) "
        "ON CONFLICT (category, key) DO UPDATE SET value = %s, is_secret = %s, updated_at = CURRENT_TIMESTAMP",
        (category, key, value, is_secret, value, is_secret)
    )
    return {"status": "saved", "category": category, "key": key}


def get_category_settings(category, mask_secrets=True):
    """Get all settings for a category. Masks secret values by default."""
    ensure_settings_table()
    results = query(
        "SELECT key, value, is_secret, updated_at FROM platform_settings WHERE category = %s ORDER BY key",
        (category,)
    )
    settings = {}
    for r in results:
        if mask_secrets and r["is_secret"] and r["value"]:
            settings[r["key"]] = "••••••" + r["value"][-4:] if len(r["value"]) > 4 else "••••••"
        else:
            settings[r["key"]] = r["value"]
    return settings


def get_all_settings(mask_secrets=True):
    """Get all settings grouped by category."""
    ensure_settings_table()
    results = query(
        "SELECT category, key, value, is_secret, updated_at FROM platform_settings ORDER BY category, key"
    )
    grouped = {}
    for r in results:
        cat = r["category"]
        if cat not in grouped:
            grouped[cat] = {}
        if mask_secrets and r["is_secret"] and r["value"]:
            grouped[cat][r["key"]] = "••••••" + r["value"][-4:] if len(r["value"]) > 4 else "••••••"
        else:
            grouped[cat][r["key"]] = r["value"]
    return grouped


def delete_setting(category, key):
    """Delete a setting."""
    execute(
        "DELETE FROM platform_settings WHERE category = %s AND key = %s",
        (category, key)
    )
    return {"status": "deleted", "category": category, "key": key}


def save_smtp_config(host, port, username, password, from_email, use_tls=True):
    """Save SMTP email configuration."""
    set_setting("smtp", "host", host)
    set_setting("smtp", "port", str(port))
    set_setting("smtp", "username", username)
    set_setting("smtp", "password", password, is_secret=True)
    set_setting("smtp", "from_email", from_email)
    set_setting("smtp", "use_tls", str(use_tls))
    return {"status": "saved", "category": "smtp"}


def save_telegram_config(bot_token, default_chat_id=None):
    """Save Telegram bot configuration."""
    set_setting("telegram", "bot_token", bot_token, is_secret=True)
    if default_chat_id:
        set_setting("telegram", "default_chat_id", default_chat_id)
    return {"status": "saved", "category": "telegram"}


def save_slack_config(webhook_url, default_channel=None):
    """Save Slack webhook configuration."""
    set_setting("slack", "webhook_url", webhook_url, is_secret=True)
    if default_channel:
        set_setting("slack", "default_channel", default_channel)
    return {"status": "saved", "category": "slack"}


def save_discord_config(webhook_url):
    """Save Discord webhook configuration."""
    set_setting("discord", "webhook_url", webhook_url, is_secret=True)
    return {"status": "saved", "category": "discord"}


def test_smtp():
    """Test SMTP connection."""
    import smtplib
    try:
        host = get_setting("smtp", "host")
        port = int(get_setting("smtp", "port") or 587)
        username = get_setting("smtp", "username")
        password = query(
            "SELECT value FROM platform_settings WHERE category = 'smtp' AND key = 'password'",
        )[0]["value"]
        use_tls = get_setting("smtp", "use_tls") == "True"

        if not host or not username:
            return {"status": "error", "message": "SMTP not configured"}

        server = smtplib.SMTP(host, port, timeout=10)
        if use_tls:
            server.starttls()
        server.login(username, password)
        server.quit()
        return {"status": "ok", "message": "SMTP connection successful"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def test_telegram():
    """Test Telegram bot connection."""
    import httpx
    try:
        token = query(
            "SELECT value FROM platform_settings WHERE category = 'telegram' AND key = 'bot_token'",
        )[0]["value"]
        if not token:
            return {"status": "error", "message": "Telegram not configured"}
        resp = httpx.get(f"https://api.telegram.org/bot{token}/getMe", timeout=10.0)
        data = resp.json()
        if data.get("ok"):
            return {"status": "ok", "bot_name": data["result"]["username"]}
        return {"status": "error", "message": data.get("description", "Unknown error")}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def test_slack():
    """Test Slack webhook."""
    import httpx
    try:
        url = query(
            "SELECT value FROM platform_settings WHERE category = 'slack' AND key = 'webhook_url'",
        )[0]["value"]
        if not url:
            return {"status": "error", "message": "Slack not configured"}
        resp = httpx.post(url, json={"text": "Maicha test: Slack integration working!"}, timeout=10.0)
        if resp.status_code == 200:
            return {"status": "ok", "message": "Slack message sent"}
        return {"status": "error", "message": f"HTTP {resp.status_code}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def test_discord():
    """Test Discord webhook."""
    import httpx
    try:
        url = query(
            "SELECT value FROM platform_settings WHERE category = 'discord' AND key = 'webhook_url'",
        )[0]["value"]
        if not url:
            return {"status": "error", "message": "Discord not configured"}
        resp = httpx.post(url, json={"content": "Maicha test: Discord integration working!"}, timeout=10.0)
        if resp.status_code in (200, 204):
            return {"status": "ok", "message": "Discord message sent"}
        return {"status": "error", "message": f"HTTP {resp.status_code}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}
EOF

echo "Created settings_manager.py"

# ============================================
# Step 2: Add settings endpoints to api.py
# ============================================
cat >> "$AGENTS/api.py" << 'PYEOF'


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
PYEOF

echo "Added settings endpoints to api.py"

# ============================================
# Step 3: Create notification_sender.py (used by agents + n8n)
# ============================================
cat > "$AGENTS/shared/notification_sender.py" << 'EOF'
"""
Notification Sender — sends messages via configured channels.
Used by agents and n8n workflows.
"""
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import httpx
from agents.shared.database import query


def _get_raw_setting(category, key):
    """Get raw setting value (unmasked)."""
    result = query(
        "SELECT value FROM platform_settings WHERE category = %s AND key = %s",
        (category, key)
    )
    return result[0]["value"] if result else None


def send_email(to_email, subject, body, html_body=None):
    """Send an email via configured SMTP."""
    host = _get_raw_setting("smtp", "host")
    port = int(_get_raw_setting("smtp", "port") or 587)
    username = _get_raw_setting("smtp", "username")
    password = _get_raw_setting("smtp", "password")
    from_email = _get_raw_setting("smtp", "from_email")
    use_tls = _get_raw_setting("smtp", "use_tls") == "True"

    if not all([host, username, password, from_email]):
        return {"status": "error", "message": "SMTP not configured"}

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = from_email
    msg["To"] = to_email
    msg.attach(MIMEText(body, "plain"))
    if html_body:
        msg.attach(MIMEText(html_body, "html"))

    try:
        server = smtplib.SMTP(host, port, timeout=15)
        if use_tls:
            server.starttls()
        server.login(username, password)
        server.sendmail(from_email, to_email, msg.as_string())
        server.quit()
        return {"status": "sent", "to": to_email}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def send_telegram(message, chat_id=None):
    """Send a Telegram message via bot."""
    token = _get_raw_setting("telegram", "bot_token")
    chat_id = chat_id or _get_raw_setting("telegram", "default_chat_id")

    if not token or not chat_id:
        return {"status": "error", "message": "Telegram not configured (need bot_token and chat_id)"}

    try:
        resp = httpx.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            json={"chat_id": chat_id, "text": message, "parse_mode": "Markdown"},
            timeout=10.0,
        )
        data = resp.json()
        if data.get("ok"):
            return {"status": "sent", "chat_id": chat_id}
        return {"status": "error", "message": data.get("description", "Unknown error")}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def send_slack(message, channel=None):
    """Send a Slack message via webhook."""
    url = _get_raw_setting("slack", "webhook_url")
    if not url:
        return {"status": "error", "message": "Slack not configured"}

    payload = {"text": message}
    if channel:
        payload["channel"] = channel

    try:
        resp = httpx.post(url, json=payload, timeout=10.0)
        if resp.status_code == 200:
            return {"status": "sent"}
        return {"status": "error", "message": f"HTTP {resp.status_code}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def send_discord(message):
    """Send a Discord message via webhook."""
    url = _get_raw_setting("discord", "webhook_url")
    if not url:
        return {"status": "error", "message": "Discord not configured"}

    try:
        resp = httpx.post(url, json={"content": message}, timeout=10.0)
        if resp.status_code in (200, 204):
            return {"status": "sent"}
        return {"status": "error", "message": f"HTTP {resp.status_code}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def send_notification(message, channels=None):
    """Send a notification to all configured channels (or specified ones)."""
    results = {}
    all_channels = channels or ["telegram", "slack", "discord"]

    if "telegram" in all_channels:
        results["telegram"] = send_telegram(message)
    if "slack" in all_channels:
        results["slack"] = send_slack(message)
    if "discord" in all_channels:
        results["discord"] = send_discord(message)

    return results
EOF

echo "Created notification_sender.py"

# ============================================
# Step 4: Add notification send endpoint to api.py
# ============================================
cat >> "$AGENTS/api.py" << 'PYEOF'


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
PYEOF

echo "Added notification endpoints to api.py"

# ============================================
# Step 5: Add /settings proxy to nginx
# ============================================
if ! grep -q "location /settings" "$BASE/nginx/nginx.conf"; then
    sed -i '/location \/openapi.json/a\
        location /settings { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Content-Type $http_content_type; }\
        location /notify { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Content-Type $http_content_type; }' "$BASE/nginx/nginx.conf"
    echo "Added /settings and /notify to nginx"
fi

# ============================================
# Step 6: Update README.md
# ============================================
cat > README.md << 'READMEEOF'
# Maicha — AI Automation Platform

Self-hosted AI automation server with specialist agents, dynamic model management, workflow automation, and multi-channel notifications.

## Architecture

```
┌─────────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│   Maicha UI │────▶│  Nginx   │────▶│ FastAPI  │────▶│  Ollama  │
│  (Browser)  │     │ :80      │     │ :8000    │     │ :11434   │
└─────────────┘     └──────────┘     └────┬─────┘     └──────────┘
                                          │
              ┌───────────────────────────┬┴──────────────────────┐
              ▼               ▼           ▼            ▼          ▼
        ┌──────────┐   ┌──────────┐ ┌──────────┐ ┌────────┐ ┌────────┐
        │PostgreSQL│   │  Qdrant  │ │   n8n    │ │Telegram│ │ Slack  │
        │ :5432    │   │  :6333   │ │  :5678   │ │  Bot   │ │Discord │
        └──────────┘   └──────────┘ └──────────┘ └────────┘ └────────┘
```

## AI Agents

| Agent | Description |
|-------|-------------|
| Restaurant | Menu queries, food orders, reservations |
| Real Estate | Property search, inquiries, lead qualification |
| Social Media | Content generation, hashtags, scheduling |
| Marketing | Ad copy, email campaigns, blog posts |
| Video | Script generation, media jobs, render queue |
| Orchestrator | Routes tasks to the right specialist agent |

## Model Management

| Provider | Type | Models |
|----------|------|--------|
| Ollama | Local (free) | Any model from ollama.com/library |
| OpenAI | Paid API | gpt-4o, gpt-4o-mini, gpt-3.5-turbo |
| Anthropic | Paid API | claude-sonnet-4-20250514, claude-haiku-4-5-20251001 |
| DeepSeek | Paid API | deepseek-chat, deepseek-coder |
| Kimi | Paid API | moonshot-v1-8k, moonshot-v1-32k |

## Settings & Notifications

Configure communication channels from the API or UI:

### SMTP (Email)
```bash
POST /settings/smtp
{"host": "smtp.gmail.com", "port": 587, "username": "you@gmail.com",
 "password": "app-password", "from_email": "you@gmail.com", "use_tls": true}

POST /settings/smtp/test    # Test connection
POST /notify/email           # Send email
```

### Telegram
```bash
POST /settings/telegram
{"bot_token": "123456:ABC-DEF", "default_chat_id": "-100123456"}

POST /settings/telegram/test   # Test bot
POST /notify/telegram           # Send message
```

### Slack
```bash
POST /settings/slack
{"webhook_url": "https://hooks.slack.com/services/T.../B.../xxx"}

POST /settings/slack/test    # Test (sends a message)
POST /notify/slack           # Send message
```

### Discord
```bash
POST /settings/discord
{"webhook_url": "https://discord.com/api/webhooks/..."}

POST /settings/discord/test  # Test (sends a message)
POST /notify/discord         # Send message
```

### Send to All Channels
```bash
POST /notify/all
{"message": "New order received!", "channels": ["telegram", "slack", "discord"]}
```

## n8n Workflow Automation

| Workflow | Trigger | What It Does |
|----------|---------|--------------|
| Real Estate Lead Bot | Webhook | AI qualifies leads, sends follow-up emails |
| Restaurant Order Bot | Every 60s | Monitors orders, notifies kitchen |
| Social Media Content Bot | Daily 8AM | Generates multi-platform content |
| Marketing Email Bot | Weekdays 9AM | Creates newsletter content |

Access n8n: `http://YOUR_IP:5678`

## API Endpoints

### Core
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Maicha UI |
| GET | `/health` | Health check |
| POST | `/chat` | Chat with an agent |
| GET | `/docs` | Swagger API docs |

### Models
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/models` | List all models |
| POST | `/models/ollama/pull` | Pull Ollama model |
| POST | `/models/paid` | Add paid API model |
| POST | `/models/default` | Set default model |

### Settings
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/settings` | View all settings |
| POST | `/settings/smtp` | Configure SMTP |
| POST | `/settings/telegram` | Configure Telegram |
| POST | `/settings/slack` | Configure Slack |
| POST | `/settings/discord` | Configure Discord |
| POST | `/settings/{channel}/test` | Test connection |

### Notifications
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/notify/email` | Send email |
| POST | `/notify/telegram` | Send Telegram |
| POST | `/notify/slack` | Send Slack |
| POST | `/notify/discord` | Send Discord |
| POST | `/notify/all` | Send to all channels |

### Data
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/menu` | Restaurant menu |
| GET | `/properties` | Property listings |
| GET | `/orders` | Orders |
| GET | `/stats` | Statistics |

## Services (9 containers)

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 5432 | Database |
| Qdrant | 6333 | Vector DB |
| Nginx | 80 | Proxy + UI |
| Ollama | 11434 | AI models |
| Open WebUI | 3000 | Chat UI |
| Adminer | 8080 | DB admin |
| FastAPI | 8000 | REST API |
| n8n | 5678 | Workflows |

## Project Structure

```
/opt/ai-server/
├── agents/
│   ├── api.py                      # FastAPI application
│   ├── shared/
│   │   ├── base_agent.py           # Base agent class
│   │   ├── database.py             # PostgreSQL helper
│   │   ├── ollama_client.py        # Unified LLM client
│   │   ├── model_manager.py        # Model registry
│   │   ├── settings_manager.py     # Platform settings
│   │   └── notification_sender.py  # Multi-channel notifications
│   ├── restaurant/agent.py
│   ├── real_estate/agent.py
│   ├── social_media/agent.py
│   ├── marketing/agent.py
│   ├── video/agent.py
│   └── orchestrator/agent.py
├── n8n/workflows/                  # Automation templates
├── nginx/
├── docker-compose.yml
└── .env.example
```

## Roadmap

- [x] Phase 1: Git repo + project structure
- [x] Phase 2: Dynamic model management
- [x] Phase 3: n8n automation engine
- [x] Phase 4: Settings panel (SMTP, Telegram, Slack, Discord)
- [ ] Phase 5: Hermes agent + TranslateGemma (Nepali)
- [ ] Phase 6: Media pipeline (Stable Diffusion, TTS, Whisper)
- [ ] Phase 7: Social platform integration (Facebook, Instagram, TikTok)
- [ ] Phase 8: Maicha UI v2 (all features integrated)
READMEEOF

echo "Updated README.md"

# ============================================
# Step 7: Git commit + push
# ============================================
git add -A
git commit -m "Phase 4: Settings panel + multi-channel notifications

Features:
- settings_manager.py: SMTP, Telegram, Slack, Discord config stored in DB
- notification_sender.py: unified send via email/Telegram/Slack/Discord
- API endpoints: /settings/* for config, /notify/* for sending
- Test endpoints for each channel (/settings/{channel}/test)
- platform_settings table auto-created on startup
- Nginx updated with /settings and /notify proxy routes
- README updated with full settings + notification docs"

echo ""
echo "=== Phase 4 Complete ==="
echo ""
echo "Run:"
echo "  cd /opt/ai-server"
echo "  docker compose build fastapi"
echo "  docker compose up -d --force-recreate fastapi nginx"
echo "  git push"
echo ""
echo "Test:"
echo "  curl http://localhost:8000/settings"
echo "  curl -X POST http://localhost:8000/settings/smtp -H 'Content-Type: application/json' -d '{\"host\":\"smtp.gmail.com\",\"port\":587,\"username\":\"you@gmail.com\",\"password\":\"app-pass\",\"from_email\":\"you@gmail.com\"}'"
echo "  curl -X POST http://localhost:8000/settings/telegram -H 'Content-Type: application/json' -d '{\"bot_token\":\"YOUR_BOT_TOKEN\",\"default_chat_id\":\"YOUR_CHAT_ID\"}'"
echo "  curl http://localhost:8000/docs  # Swagger UI shows all new endpoints"
