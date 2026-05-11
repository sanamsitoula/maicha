import os
import json
from agents.shared.base_agent import BaseAgent
from agents.shared.database import query, execute

SYSTEM_PROMPT = """You are a professional and helpful real estate assistant.

Your responsibilities:
1. Help clients search for properties based on their criteria
2. Provide detailed property information
3. Generate compelling property descriptions
4. Qualify buyer/seller leads
5. Record client inquiries and contact information

Be professional, knowledgeable, and attentive to client needs. Always provide accurate property information from the database."""


def create_real_estate_agent(model=None):
    agent = BaseAgent(name="Real Estate Agent", system_prompt=SYSTEM_PROMPT, model=model)
    agent._conversation_id = None

    def _ensure_conversation():
        if agent._conversation_id is None:
            result = execute(
                "INSERT INTO conversations (agent_type, title, status) "
                "VALUES ('real-estate', 'Real Estate Chat', 'active') RETURNING id"
            )
            agent._conversation_id = result[0]["id"]
        return agent._conversation_id

    def _log_message(role, content, model_used=None):
        conv_id = _ensure_conversation()
        execute("INSERT INTO messages (conversation_id, role, content, model_used) VALUES (%s, %s, %s, %s)",
                (conv_id, role, content, model_used))

    def _log_event(event_type, data=None):
        execute("INSERT INTO events (event_type, source, data) VALUES (%s, 'real-estate-agent', %s)",
                (event_type, json.dumps(data or {})))

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
    agent.reset_conversation = logged_reset

    def search_properties(city=None, min_price=None, max_price=None, bedrooms=None, property_type=None, listing_type=None):
        conditions = ["status = 'active'"]
        params = []
        if city:
            conditions.append("LOWER(city) = LOWER(%s)")
            params.append(city)
        if min_price:
            conditions.append("price >= %s")
            params.append(min_price)
        if max_price:
            conditions.append("price <= %s")
            params.append(max_price)
        if bedrooms:
            conditions.append("bedrooms >= %s")
            params.append(bedrooms)
        if property_type:
            conditions.append("LOWER(property_type) = LOWER(%s)")
            params.append(property_type)
        if listing_type:
            conditions.append("LOWER(listing_type) = LOWER(%s)")
            params.append(listing_type)
        where = " AND ".join(conditions)
        results = query(
            f"SELECT title, description, property_type, listing_type, price, bedrooms, bathrooms, "
            f"area_sqft, city, state, zip_code, features FROM property_listings WHERE {where} ORDER BY created_at DESC LIMIT 10",
            tuple(params) if params else None
        )
        _log_event("property_search", {"city": city, "results": len(results)})
        return {"properties": results, "count": len(results)}

    agent.register_tool(
        name="search_properties",
        description="Search property listings. All parameters are optional filters.",
        parameters={
            "city": "optional string", "min_price": "optional number", "max_price": "optional number",
            "bedrooms": "optional integer", "property_type": "optional string - house, apartment, condo, land, commercial",
            "listing_type": "optional string - sale or rent",
        },
        function=search_properties,
    )

    def record_inquiry(property_title, contact_name, contact_email=None, contact_phone=None, message=None, inquiry_type="general"):
        props = query("SELECT id FROM property_listings WHERE LOWER(title) = LOWER(%s) LIMIT 1", (property_title,))
        if not props:
            return {"error": f"Property not found: {property_title}"}
        execute(
            "INSERT INTO property_inquiries (property_id, contact_name, contact_email, contact_phone, message, inquiry_type, status) "
            "VALUES (%s, %s, %s, %s, %s, %s, 'new')",
            (props[0]["id"], contact_name, contact_email, contact_phone, message, inquiry_type)
        )
        _log_event("lead_created", {"contact_name": contact_name, "property": property_title})
        return {"status": "recorded", "contact_name": contact_name, "property": property_title}

    agent.register_tool(
        name="record_inquiry",
        description="Record a client inquiry about a property.",
        parameters={
            "property_title": "string", "contact_name": "string",
            "contact_email": "optional string", "contact_phone": "optional string",
            "message": "optional string", "inquiry_type": "optional string - viewing, question, offer, general",
        },
        function=record_inquiry,
    )

    return agent


if __name__ == "__main__":
    from dotenv import load_dotenv
    load_dotenv("/opt/ai-server/.env")
    os.environ.setdefault("POSTGRES_HOST", "localhost")
    os.environ.setdefault("OLLAMA_BASE_URL", "http://localhost:11434")
    print("Real Estate Agent - type 'quit' to exit\n")
    agent = create_real_estate_agent()
    while True:
        user_input = input("You: ").strip()
        if not user_input: continue
        if user_input.lower() == 'quit': break
        try:
            print(f"\n{agent.name}: {agent.process_message(user_input)}\n")
        except Exception as e:
            print(f"Error: {e}\n")
