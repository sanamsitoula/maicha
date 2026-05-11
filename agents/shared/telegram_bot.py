"""
Telegram Order Bot — multi-step conversational ordering via Telegram.
Collects: food items, customer name, mobile number, address, remarks.
Saves to orders table. Notifies Discord.
"""
import json
import os
from agents.shared.database import query, execute
from agents.shared.notification_sender import send_discord, send_telegram

# In-memory conversation state (chat_id -> state dict)
# In production you'd use Redis, but for our setup this works fine
CONVERSATIONS = {}


def get_state(chat_id):
    return CONVERSATIONS.get(str(chat_id), {"step": "idle"})


def set_state(chat_id, state):
    CONVERSATIONS[str(chat_id)] = state


def clear_state(chat_id):
    CONVERSATIONS.pop(str(chat_id), None)


def get_menu_text():
    """Get formatted menu for Telegram."""
    items = query(
        "SELECT name, price, category, dietary_tags FROM menu_items "
        "WHERE is_available = true ORDER BY category, name"
    )
    if not items:
        return "Sorry, no menu items available right now."

    text = "\U0001F37D *THE AI BISTRO — MENU*\n\n"
    current_cat = ""
    for item in items:
        if item["category"] != current_cat:
            current_cat = item["category"]
            text += f"\n*{current_cat.upper()}*\n"
        tags = ""
        if item.get("dietary_tags"):
            tags = " " + " ".join(f"[{t}]" for t in item["dietary_tags"])
        text += f"  \U00002022 {item['name']} — ${item['price']}{tags}\n"

    text += "\n\U0001F4DD To order, type: /order"
    return text


def process_telegram_message(chat_id, user_name, text):
    """
    Process incoming Telegram message through the ordering state machine.
    Returns the reply text to send back.
    """
    chat_id = str(chat_id)
    state = get_state(chat_id)
    text = text.strip()

    # ── Command handlers ──

    if text.lower() == "/start":
        clear_state(chat_id)
        return (
            f"Welcome to *The AI Bistro*, {user_name}! \U0001F44B\n\n"
            f"I can help you order food for delivery.\n\n"
            f"\U0001F4CB /menu — View our menu\n"
            f"\U0001F6D2 /order — Place an order\n"
            f"\U00002753 /help — Get help\n"
            f"\U0000274C /cancel — Cancel current order"
        )

    if text.lower() == "/menu":
        return get_menu_text()

    if text.lower() == "/cancel":
        clear_state(chat_id)
        return "\U0000274C Order cancelled. Type /order to start a new one."

    if text.lower() == "/help":
        return (
            "\U00002753 *How to order:*\n\n"
            "1. Type /menu to see available items\n"
            "2. Type /order to start ordering\n"
            "3. I'll ask for your items, name, phone, address\n"
            "4. Confirm and your order is placed!\n\n"
            "Type /cancel anytime to start over."
        )

    if text.lower() == "/order" or (state["step"] == "idle" and "order" in text.lower()):
        set_state(chat_id, {
            "step": "ask_items",
            "user_name": user_name,
            "data": {}
        })
        menu = get_menu_text()
        return (
            f"{menu}\n\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"\U0001F37D *What would you like to order?*\n"
            f"List the items (e.g. 'Neural Burger, Algorithm Salad')"
        )

    # ── Multi-step order flow ──

    if state["step"] == "ask_items":
        state["data"]["items"] = text
        state["step"] = "ask_name"
        set_state(chat_id, state)
        return "\U0001F464 *What is your name?*"

    if state["step"] == "ask_name":
        state["data"]["customer_name"] = text
        state["step"] = "ask_phone"
        set_state(chat_id, state)
        return "\U0001F4F1 *What is your mobile number?*"

    if state["step"] == "ask_phone":
        state["data"]["mobile"] = text
        state["step"] = "ask_address"
        set_state(chat_id, state)
        return "\U0001F3E0 *What is your delivery address?*"

    if state["step"] == "ask_address":
        state["data"]["address"] = text
        state["step"] = "ask_remarks"
        set_state(chat_id, state)
        return "\U0001F4DD *Any special remarks or instructions?*\n(Type 'none' if no remarks)"

    if state["step"] == "ask_remarks":
        remarks = text if text.lower() != "none" else None
        state["data"]["remarks"] = remarks
        state["step"] = "confirm"
        set_state(chat_id, state)

        d = state["data"]
        return (
            f"\U0001F4CB *ORDER SUMMARY*\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"\U0001F37D Items: {d['items']}\n"
            f"\U0001F464 Name: {d['customer_name']}\n"
            f"\U0001F4F1 Phone: {d['mobile']}\n"
            f"\U0001F3E0 Address: {d['address']}\n"
            f"\U0001F4DD Remarks: {d.get('remarks') or 'None'}\n"
            f"━━━━━━━━━━━━━━━━━━━━\n\n"
            f"*Confirm this order?* (yes/no)"
        )

    if state["step"] == "confirm":
        if text.lower() in ("yes", "y", "confirm", "ok"):
            d = state["data"]
            order_result = save_order(d, chat_id)

            if order_result["status"] == "ok":
                notify_discord_order(d, order_result["order_id"])
                clear_state(chat_id)
                return (
                    f"\U00002705 *ORDER CONFIRMED!*\n\n"
                    f"Order ID: `{order_result['order_id'][:8]}`\n"
                    f"Total: ${order_result['total']}\n\n"
                    f"Thank you, {d['customer_name']}! "
                    f"Your food is being prepared. \U0001F373\n\n"
                    f"Type /order to place another order."
                )
            else:
                clear_state(chat_id)
                return f"\U0000274C Error placing order: {order_result.get('error', 'Unknown error')}. Please try /order again."

        elif text.lower() in ("no", "n", "cancel"):
            clear_state(chat_id)
            return "\U0000274C Order cancelled. Type /order to start over."
        else:
            return "Please reply *yes* or *no* to confirm your order."

    # ── Default: unknown message ──
    return (
        f"I didn't understand that. Try:\n\n"
        f"\U0001F4CB /menu — View menu\n"
        f"\U0001F6D2 /order — Place an order\n"
        f"\U00002753 /help — Get help"
    )


def save_order(data, chat_id):
    """Save order to database."""
    try:
        restaurants = query("SELECT id FROM restaurants LIMIT 1")
        if not restaurants:
            return {"status": "error", "error": "No restaurant configured"}
        restaurant_id = restaurants[0]["id"]

        # Parse items and calculate total
        item_names = [i.strip() for i in data["items"].split(",")]
        order_items = []
        subtotal = 0

        for item_name in item_names:
            menu_item = query(
                "SELECT id, name, price FROM menu_items WHERE LOWER(name) LIKE LOWER(%s) AND is_available = true",
                (f"%{item_name}%",)
            )
            if menu_item:
                mi = menu_item[0]
                item_total = float(mi["price"])
                subtotal += item_total
                order_items.append({
                    "menu_item_id": mi["id"],
                    "name": mi["name"],
                    "unit_price": float(mi["price"]),
                    "total_price": item_total,
                })

        if not order_items:
            # Still save the order even if items don't match exactly
            subtotal = 0

        tax = round(subtotal * 0.0825, 2)
        total = round(subtotal + tax, 2)

        special_instructions = ""
        if data.get("address"):
            special_instructions += f"Address: {data['address']}"
        if data.get("mobile"):
            special_instructions += f" | Phone: {data['mobile']}"
        if data.get("remarks"):
            special_instructions += f" | Remarks: {data['remarks']}"

        order = execute(
            "INSERT INTO orders (restaurant_id, customer_name, customer_phone, order_type, "
            "subtotal, tax, total, special_instructions, status) "
            "VALUES (%s, %s, %s, 'delivery', %s, %s, %s, %s, 'confirmed') RETURNING id",
            (restaurant_id, data["customer_name"], data.get("mobile"),
             subtotal, tax, total, special_instructions)
        )
        order_id = str(order[0]["id"])

        for oi in order_items:
            execute(
                "INSERT INTO order_items (order_id, menu_item_id, quantity, unit_price, total_price) "
                "VALUES (%s, %s, 1, %s, %s)",
                (order_id, oi["menu_item_id"], oi["unit_price"], oi["total_price"])
            )

        # Log event
        execute(
            "INSERT INTO events (event_type, source, data) VALUES (%s, %s, %s)",
            ("order_placed", "telegram-bot", json.dumps({
                "order_id": order_id,
                "customer": data["customer_name"],
                "phone": data.get("mobile"),
                "address": data.get("address"),
                "items": data["items"],
                "total": total,
                "chat_id": chat_id,
            }))
        )

        return {"status": "ok", "order_id": order_id, "total": total}

    except Exception as e:
        return {"status": "error", "error": str(e)}


def notify_discord_order(data, order_id):
    """Send order notification to Discord."""
    msg = (
        f"\U0001F37D **NEW ORDER FROM TELEGRAM**\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"**Order ID:** {order_id[:8]}\n"
        f"**Customer:** {data['customer_name']}\n"
        f"**Phone:** {data.get('mobile', 'N/A')}\n"
        f"**Address:** {data.get('address', 'N/A')}\n"
        f"**Items:** {data['items']}\n"
        f"**Remarks:** {data.get('remarks') or 'None'}\n"
        f"━━━━━━━━━━━━━━━━━━━━"
    )
    send_discord(msg)

    # Also send email notification if SMTP is configured
    try:
        from agents.shared.notification_sender import send_email
        from agents.shared.settings_manager import get_setting
        from_email = get_setting("smtp", "from_email")
        if from_email:
            send_email(
                from_email,
                f"New Order: {data['customer_name']} - {data['items']}",
                f"Order ID: {order_id}\nCustomer: {data['customer_name']}\nPhone: {data.get('mobile')}\nAddress: {data.get('address')}\nItems: {data['items']}\nRemarks: {data.get('remarks', 'None')}"
            )
    except Exception:
        pass
