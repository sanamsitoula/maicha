import os
import json
from agents.shared.base_agent import BaseAgent
from agents.shared.database import query, execute

SYSTEM_PROMPT = """You are an expert marketing copywriter and content strategist.

Your responsibilities:
1. Write compelling ad copy for various platforms
2. Create email marketing campaigns
3. Generate blog post drafts
4. Adapt messaging for different audiences
5. Store all generated content with versioning

Be persuasive, clear, and results-oriented."""


def create_marketing_agent(model=None):
    agent = BaseAgent(name="Marketing Agent", system_prompt=SYSTEM_PROMPT, model=model)
    agent._conversation_id = None

    def _ensure_conversation():
        if agent._conversation_id is None:
            result = execute(
                "INSERT INTO conversations (agent_type, title, status) "
                "VALUES ('marketing', 'Marketing Chat', 'active') RETURNING id"
            )
            agent._conversation_id = result[0]["id"]
        return agent._conversation_id

    def _log_message(role, content, model_used=None):
        conv_id = _ensure_conversation()
        execute("INSERT INTO messages (conversation_id, role, content, model_used) VALUES (%s, %s, %s, %s)",
                (conv_id, role, content, model_used))

    def _log_event(event_type, data=None):
        execute("INSERT INTO events (event_type, source, data) VALUES (%s, 'marketing-agent', %s)",
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

    def save_content(content_type, title, body, platform=None):
        result = execute(
            "INSERT INTO agent_memory (agent_type, memory_type, content, metadata) "
            "VALUES ('marketing', %s, %s, %s) RETURNING id",
            (content_type, f"Title: {title}\n\n{body}", json.dumps({"title": title, "platform": platform, "type": content_type}))
        )
        _log_event("content_generated", {"type": content_type, "title": title})
        return {"content_id": str(result[0]["id"]), "title": title, "status": "saved"}

    agent.register_tool(
        name="save_content",
        description="Save generated marketing content to the database.",
        parameters={
            "content_type": "string - ad_copy, email, blog_post, campaign, tagline",
            "title": "string", "body": "string", "platform": "optional string",
        },
        function=save_content,
    )

    def get_saved_content(content_type=None, limit=10):
        if content_type:
            results = query(
                "SELECT id, memory_type, content, metadata, created_at FROM agent_memory "
                "WHERE agent_type = 'marketing' AND memory_type = %s ORDER BY created_at DESC LIMIT %s",
                (content_type, limit))
        else:
            results = query(
                "SELECT id, memory_type, content, metadata, created_at FROM agent_memory "
                "WHERE agent_type = 'marketing' ORDER BY created_at DESC LIMIT %s", (limit,))
        return {"content_items": results, "count": len(results)}

    agent.register_tool(
        name="get_saved_content",
        description="Retrieve previously saved marketing content.",
        parameters={"content_type": "optional string", "limit": "optional integer (default 10)"},
        function=get_saved_content,
    )

    return agent


if __name__ == "__main__":
    from dotenv import load_dotenv
    load_dotenv("/opt/ai-server/.env")
    os.environ.setdefault("POSTGRES_HOST", "localhost")
    os.environ.setdefault("OLLAMA_BASE_URL", "http://localhost:11434")
    print("Marketing Agent - type 'quit' to exit\n")
    agent = create_marketing_agent()
    while True:
        user_input = input("You: ").strip()
        if not user_input: continue
        if user_input.lower() == 'quit': break
        try:
            print(f"\n{agent.name}: {agent.process_message(user_input)}\n")
        except Exception as e:
            print(f"Error: {e}\n")
