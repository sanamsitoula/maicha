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
