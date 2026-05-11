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
