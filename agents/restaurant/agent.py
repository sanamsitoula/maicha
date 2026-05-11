"""
Restaurant Ordering Agent - with full database logging
"""

import os
import json
import uuid
from agents.shared.base_agent import BaseAgent
from agents.shared.database import query, execute


SYSTEM_PROMPT = """You are a friendly and efficient restaurant ordering assistant for "The AI Bistro".

Your responsibilities:
1. Help customers view the menu
2. Take food orders
3. Answer questions about dishes (ingredients, dietary info)
4. Calculate order totals
5. Handle reservations

Be warm, helpful, and concise. When a customer wants to order, confirm each item and the total before placing the order. Always mention dietary information when relevant.

When you need data from the restaurant system, use the available tools. Don't make up menu items or prices — always check the real menu first."""


def create_restaurant_agent(model=None):
    agent = BaseAgent(
        name="Restaurant Agent",
        system_prompt=SYSTEM_PROMPT,
        model=model,
    )

    agent._conversation_id = None
    agent._customer_name = None

    def _ensure_conversation():
        if agent._conversation_id is None:
            result = execute(
                "INSERT INTO conversations (agent_type, title, status) "
                "VALUES ('restaurant', 'Restaurant Chat', 'active') RETURNING id"
            )
            agent._conversation_id = result[0]["id"]
        return agent._conversation_id

    def _log_message(role, content, model_used=None):
        conv_id = _ensure_conversation()
        execute(
            "INSERT INTO messages (conversation_id, role, content, model_used) "
            "VALUES (%s, %s, %s, %s)",
            (conv_id, role, content, model_used)
        )

    def _log_event(event_type, data=None):
        execute(
            "INSERT INTO events (event_type, source, data) VALUES (%s, 'restaurant-agent', %s)",
            (event_type, json.dumps(data or {}))
        )

    original_process = agent.process_message

    def logged_process_message(user_message):
        _log_message("user", user_message)
        response = original_process(user_message)
        _log_message("assistant", response, model_used=agent.model or os.getenv("DEFAULT_MODEL", "llama3.2:3b"))
        return response

    agent.process_message = logged_process_message

    def logged_reset():
        agent.conversation_history = []
        agent._conversation_id = None
        agent._customer_name = None

    agent.reset_conversation = logged_reset

    def get_menu(category=None):
        if category:
            items = query(
                "SELECT name, description, category, price, dietary_tags "
                "FROM menu_items WHERE is_available = true AND LOWER(category) = LOWER(%s) "
                "ORDER BY sort_order, name",
                (category,)
            )
        else:
            items = query(
                "SELECT name, description, category, price, dietary_tags "
                "FROM menu_items WHERE is_available = true "
                "ORDER BY category, sort_order, name"
            )
        _log_event("menu_viewed", {"category": category, "items_returned": len(items)})
        return {"menu_items": items, "count": len(items)}

    agent.register_tool(
        name="get_menu",
        description="Get the restaurant menu. Can filter by category (appetizer, main, dessert, drink, side).",
        parameters={"category": "optional - filter by category name"},
        function=get_menu,
    )

    def place_order(customer_name, items, special_instructions=None):
        restaurants = query("SELECT id FROM restaurants LIMIT 1")
        if not restaurants:
            return {"error": "No restaurant configured"}
        restaurant_id = restaurants[0]["id"]
        agent._customer_name = customer_name

        order_items = []
        subtotal = 0

        for item in items:
            menu_item = query(
                "SELECT id, name, price FROM menu_items WHERE LOWER(name) = LOWER(%s) AND is_available = true",
                (item["name"],)
            )
            if not menu_item:
                return {"error": f"Menu item not found: {item['name']}"}

            menu_item = menu_item[0]
            qty = item.get("quantity", 1)
            item_total = float(menu_item["price"]) * qty
            subtotal += item_total
            order_items.append({
                "menu_item_id": menu_item["id"],
                "name": menu_item["name"],
                "quantity": qty,
                "unit_price": float(menu_item["price"]),
                "total_price": item_total,
            })

        tax = round(subtotal * 0.0825, 2)
        total = round(subtotal + tax, 2)
        conv_id = _ensure_conversation()

        order = execute(
            "INSERT INTO orders (restaurant_id, customer_name, order_type, subtotal, tax, total, special_instructions, status, conversation_id) "
            "VALUES (%s, %s, 'dine-in', %s, %s, %s, %s, 'confirmed', %s) RETURNING id",
            (restaurant_id, customer_name, subtotal, tax, total, special_instructions, conv_id)
        )
        order_id = order[0]["id"]

        for oi in order_items:
            execute(
                "INSERT INTO order_items (order_id, menu_item_id, quantity, unit_price, total_price) "
                "VALUES (%s, %s, %s, %s, %s)",
                (order_id, oi["menu_item_id"], oi["quantity"], oi["unit_price"], oi["total_price"])
            )

        _log_event("order_placed", {
            "order_id": str(order_id),
            "customer_name": customer_name,
            "total": total,
            "item_count": len(order_items),
        })

        return {
            "order_id": str(order_id),
            "customer_name": customer_name,
            "items": [{"name": oi["name"], "qty": oi["quantity"], "price": oi["total_price"]} for oi in order_items],
            "subtotal": subtotal,
            "tax": tax,
            "total": total,
            "status": "confirmed",
        }

    agent.register_tool(
        name="place_order",
        description="Place a food order. Requires customer name and list of items with quantities.",
        parameters={
            "customer_name": "string - customer's name",
            "items": 'list of {"name": "menu item name", "quantity": number}',
            "special_instructions": "optional string - any special requests",
        },
        function=place_order,
    )

    def check_order(order_id):
        orders = query(
            "SELECT o.id, o.customer_name, o.status, o.total, o.created_at, "
            "json_agg(json_build_object('name', mi.name, 'quantity', oi.quantity, 'price', oi.total_price)) as items "
            "FROM orders o "
            "JOIN order_items oi ON o.id = oi.order_id "
            "JOIN menu_items mi ON oi.menu_item_id = mi.id "
            "WHERE o.id = %s::uuid "
            "GROUP BY o.id",
            (order_id,)
        )
        if not orders:
            return {"error": "Order not found"}
        return orders[0]

    agent.register_tool(
        name="check_order",
        description="Check the status of an existing order by order ID.",
        parameters={"order_id": "string - the order's UUID"},
        function=check_order,
    )

    def make_reservation(customer_name, party_size, date, time, customer_phone=None):
        restaurants = query("SELECT id FROM restaurants LIMIT 1")
        if not restaurants:
            return {"error": "No restaurant configured"}

        conv_id = _ensure_conversation()
        reservation = execute(
            "INSERT INTO reservations (restaurant_id, customer_name, customer_phone, party_size, reservation_date, reservation_time, status, conversation_id) "
            "VALUES (%s, %s, %s, %s, %s, %s, 'confirmed', %s) RETURNING id, reservation_date, reservation_time",
            (restaurants[0]["id"], customer_name, customer_phone, party_size, date, time, conv_id)
        )

        _log_event("reservation_made", {
            "customer_name": customer_name,
            "party_size": party_size,
            "date": date,
            "time": time,
        })

        return {
            "reservation_id": str(reservation[0]["id"]),
            "customer_name": customer_name,
            "party_size": party_size,
            "date": str(reservation[0]["reservation_date"]),
            "time": str(reservation[0]["reservation_time"]),
            "status": "confirmed",
        }

    agent.register_tool(
        name="make_reservation",
        description="Make a restaurant reservation. Requires customer name, party size, date (YYYY-MM-DD), and time (HH:MM).",
        parameters={
            "customer_name": "string",
            "party_size": "integer",
            "date": "string - format YYYY-MM-DD",
            "time": "string - format HH:MM",
            "customer_phone": "optional string",
        },
        function=make_reservation,
    )

    return agent


if __name__ == "__main__":
    from dotenv import load_dotenv

    load_dotenv("/opt/ai-server/.env")
    os.environ.setdefault("POSTGRES_HOST", "localhost")
    os.environ.setdefault("OLLAMA_BASE_URL", "http://localhost:11434")

    print("=" * 50)
    print("The AI Bistro - Restaurant Agent")
    print("=" * 50)
    print("Type your message (or 'quit' to exit, 'reset' to start over)\n")

    agent = create_restaurant_agent()

    while True:
        user_input = input("You: ").strip()
        if not user_input:
            continue
        if user_input.lower() == 'quit':
            print("Goodbye!")
            break
        if user_input.lower() == 'reset':
            agent.reset_conversation()
            print("Conversation reset.\n")
            continue

        print(f"\n{agent.name}: ", end="", flush=True)
        try:
            response = agent.process_message(user_input)
            print(response)
        except Exception as e:
            print(f"Error: {e}")
        print()
