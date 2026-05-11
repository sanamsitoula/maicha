#!/bin/bash
set -e
echo "=== Phase 4 Patch: Adding WhatsApp Support ==="

BASE="/opt/ai-server"
AGENTS="$BASE/agents"
cd "$BASE"

# ============================================
# Step 1: Add WhatsApp to settings_manager.py
# ============================================
cat >> "$AGENTS/shared/settings_manager.py" << 'EOF'


def save_whatsapp_config(phone_number_id, access_token, verify_token=None):
    """Save WhatsApp Business API configuration.
    
    Uses Meta's WhatsApp Business Cloud API.
    - phone_number_id: Your WhatsApp Business phone number ID
    - access_token: Permanent token from Meta Developer portal
    - verify_token: For webhook verification (optional)
    """
    set_setting("whatsapp", "phone_number_id", phone_number_id)
    set_setting("whatsapp", "access_token", access_token, is_secret=True)
    if verify_token:
        set_setting("whatsapp", "verify_token", verify_token, is_secret=True)
    return {"status": "saved", "category": "whatsapp"}


def test_whatsapp():
    """Test WhatsApp Business API connection."""
    import httpx
    try:
        phone_id = get_setting("whatsapp", "phone_number_id")
        token = query(
            "SELECT value FROM platform_settings WHERE category = 'whatsapp' AND key = 'access_token'",
        )[0]["value"]
        if not phone_id or not token:
            return {"status": "error", "message": "WhatsApp not configured"}
        resp = httpx.get(
            f"https://graph.facebook.com/v18.0/{phone_id}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10.0,
        )
        data = resp.json()
        if "id" in data:
            return {"status": "ok", "phone_number_id": data["id"], "display_phone": data.get("display_phone_number", "unknown")}
        return {"status": "error", "message": data.get("error", {}).get("message", "Unknown error")}
    except Exception as e:
        return {"status": "error", "message": str(e)}
EOF

echo "Added WhatsApp to settings_manager.py"

# ============================================
# Step 2: Add WhatsApp to notification_sender.py
# ============================================
cat >> "$AGENTS/shared/notification_sender.py" << 'EOF'


def send_whatsapp(to_phone, message):
    """Send a WhatsApp message via Meta Business API.
    
    Args:
        to_phone: recipient phone number with country code (e.g. '9779812345678')
        message: text message to send
    """
    phone_id = _get_raw_setting("whatsapp", "phone_number_id")
    token = _get_raw_setting("whatsapp", "access_token")

    if not phone_id or not token:
        return {"status": "error", "message": "WhatsApp not configured"}

    try:
        resp = httpx.post(
            f"https://graph.facebook.com/v18.0/{phone_id}/messages",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            json={
                "messaging_product": "whatsapp",
                "to": to_phone,
                "type": "text",
                "text": {"body": message},
            },
            timeout=15.0,
        )
        data = resp.json()
        if "messages" in data:
            return {"status": "sent", "to": to_phone, "message_id": data["messages"][0]["id"]}
        return {"status": "error", "message": data.get("error", {}).get("message", "Unknown error")}
    except Exception as e:
        return {"status": "error", "message": str(e)}
EOF

# Also update the send_notification function to include whatsapp
python3 << 'PYFIX'
import re

filepath = "/opt/ai-server/agents/shared/notification_sender.py"
with open(filepath, "r") as f:
    content = f.read()

# Update send_notification to include whatsapp
old = '''    all_channels = channels or ["telegram", "slack", "discord"]

    if "telegram" in all_channels:
        results["telegram"] = send_telegram(message)
    if "slack" in all_channels:
        results["slack"] = send_slack(message)
    if "discord" in all_channels:
        results["discord"] = send_discord(message)'''

new = '''    all_channels = channels or ["telegram", "slack", "discord"]

    if "telegram" in all_channels:
        results["telegram"] = send_telegram(message)
    if "slack" in all_channels:
        results["slack"] = send_slack(message)
    if "discord" in all_channels:
        results["discord"] = send_discord(message)
    if "whatsapp" in all_channels:
        results["whatsapp"] = {"status": "skipped", "message": "WhatsApp requires a recipient phone number. Use /notify/whatsapp directly."}'''

content = content.replace(old, new)

with open(filepath, "w") as f:
    f.write(content)

print("Updated send_notification with WhatsApp")
PYFIX

echo "Added WhatsApp to notification_sender.py"

# ============================================
# Step 3: Add WhatsApp endpoints to api.py
# ============================================
cat >> "$AGENTS/api.py" << 'PYEOF'


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
PYEOF

echo "Added WhatsApp endpoints to api.py"

# ============================================
# Step 4: Update README — add WhatsApp section
# ============================================
python3 << 'PYFIX2'
filepath = "/opt/ai-server/README.md"
with open(filepath, "r") as f:
    content = f.read()

# Add WhatsApp section after Discord section
whatsapp_docs = """
### WhatsApp (Business API)
```bash
# Requires Meta Business account + WhatsApp Business API setup
# Get credentials from https://developers.facebook.com/

POST /settings/whatsapp
{"phone_number_id": "1234567890", "access_token": "EAAx...", "verify_token": "my-verify-token"}

POST /settings/whatsapp/test   # Test API connection
POST /notify/whatsapp           # Send message
{"to_phone": "9779812345678", "message": "Hello from Maicha!"}
```
"""

content = content.replace(
    "### Send to All Channels",
    whatsapp_docs + "\n### Send to All Channels"
)

# Update settings table
content = content.replace(
    "| POST | `/settings/discord` | Configure Discord |",
    "| POST | `/settings/discord` | Configure Discord |\n| POST | `/settings/whatsapp` | Configure WhatsApp |"
)
content = content.replace(
    "| POST | `/notify/discord` | Send Discord |",
    "| POST | `/notify/discord` | Send Discord |\n| POST | `/notify/whatsapp` | Send WhatsApp |"
)

# Update architecture
content = content.replace(
    "│ Slack  │\n        │Discord │",
    "│ Slack  │\n        │Discord │\n        │WhatsApp│"
)

with open(filepath, "w") as f:
    f.write(content)

print("Updated README with WhatsApp docs")
PYFIX2

# ============================================
# Step 5: Update settings categories in api.py
# ============================================
python3 << 'PYFIX3'
filepath = "/opt/ai-server/agents/api.py"
with open(filepath, "r") as f:
    content = f.read()

# Add whatsapp to categories dict
old_cat = '"discord": {"label": "Discord", "description": "Send notifications via Discord webhook"},'
new_cat = '"discord": {"label": "Discord", "description": "Send notifications via Discord webhook"},\n            "whatsapp": {"label": "WhatsApp", "description": "Send messages via WhatsApp Business API"},'

content = content.replace(old_cat, new_cat)

with open(filepath, "w") as f:
    f.write(content)

print("Updated settings categories in api.py")
PYFIX3

# ============================================
# Step 6: Git commit
# ============================================
git add -A
git commit -m "Phase 4: Add WhatsApp Business API support

- WhatsApp config: phone_number_id + access_token stored in settings
- WhatsApp sender via Meta Graph API v18.0
- Endpoints: POST /settings/whatsapp, /settings/whatsapp/test, /notify/whatsapp
- README updated with WhatsApp setup docs
- All 6 channels now supported: SMTP, Telegram, Slack, Discord, WhatsApp, Email"

echo ""
echo "=== WhatsApp Added to Phase 4 ==="
echo ""
echo "Run:"
echo "  cd /opt/ai-server"
echo "  docker compose build fastapi"
echo "  docker compose up -d --force-recreate fastapi"
echo "  git push"
echo ""
echo "Test:"
echo "  curl http://localhost:8000/settings"
echo ""
echo "All 6 notification channels:"
echo "  POST /settings/smtp      → Email"
echo "  POST /settings/telegram  → Telegram Bot"
echo "  POST /settings/slack     → Slack Webhook"
echo "  POST /settings/discord   → Discord Webhook"
echo "  POST /settings/whatsapp  → WhatsApp Business API"
echo "  POST /notify/all         → Send to all channels at once"
