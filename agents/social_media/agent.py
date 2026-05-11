import os
import json
from agents.shared.base_agent import BaseAgent
from agents.shared.database import query, execute

SYSTEM_PROMPT = """You are a creative social media content specialist.

Your responsibilities:
1. Generate engaging captions for Instagram, TikTok, Facebook, Twitter, and LinkedIn
2. Create relevant hashtag sets for each platform
3. Write video scripts for short-form content
4. Schedule content for posting
5. Adapt tone and style per platform

Be creative, trendy, and platform-aware."""


def create_social_media_agent(model=None):
    agent = BaseAgent(name="Social Media Agent", system_prompt=SYSTEM_PROMPT, model=model)
    agent._conversation_id = None

    def _ensure_conversation():
        if agent._conversation_id is None:
            result = execute(
                "INSERT INTO conversations (agent_type, title, status) "
                "VALUES ('social-media', 'Social Media Chat', 'active') RETURNING id"
            )
            agent._conversation_id = result[0]["id"]
        return agent._conversation_id

    def _log_message(role, content, model_used=None):
        conv_id = _ensure_conversation()
        execute("INSERT INTO messages (conversation_id, role, content, model_used) VALUES (%s, %s, %s, %s)",
                (conv_id, role, content, model_used))

    def _log_event(event_type, data=None):
        execute("INSERT INTO events (event_type, source, data) VALUES (%s, 'social-media-agent', %s)",
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

    def create_content(platform, topic, content_type="post", tone=None):
        result = execute(
            "INSERT INTO content_queue (platform, content_type, generation_prompt, status, ai_generated) "
            "VALUES (%s, %s, %s, 'draft', true) RETURNING id",
            (platform, content_type, f"Topic: {topic}, Tone: {tone or 'default'}")
        )
        _log_event("content_created", {"platform": platform, "topic": topic})
        return {
            "content_id": str(result[0]["id"]), "platform": platform, "topic": topic,
            "instruction": f"Generate a {content_type} for {platform} about: {topic}. Tone: {tone or 'engaging'}. Include caption and hashtags."
        }

    agent.register_tool(
        name="create_content",
        description="Create a new social media content draft.",
        parameters={
            "platform": "string - instagram, tiktok, facebook, twitter, linkedin",
            "topic": "string - what the content is about",
            "content_type": "optional string - post, story, reel, tweet (default: post)",
            "tone": "optional string - professional, casual, funny, inspirational",
        },
        function=create_content,
    )

    def get_content_queue(platform=None, status=None):
        conditions = []
        params = []
        if platform:
            conditions.append("LOWER(platform) = LOWER(%s)")
            params.append(platform)
        if status:
            conditions.append("LOWER(status) = LOWER(%s)")
            params.append(status)
        where = " AND ".join(conditions) if conditions else "1=1"
        results = query(
            f"SELECT id, platform, content_type, caption, hashtags, scheduled_for, status "
            f"FROM content_queue WHERE {where} ORDER BY created_at DESC LIMIT 20",
            tuple(params) if params else None
        )
        return {"content_items": results, "count": len(results)}

    agent.register_tool(
        name="get_content_queue",
        description="View scheduled and draft content.",
        parameters={"platform": "optional string", "status": "optional string - draft, scheduled, published"},
        function=get_content_queue,
    )

    return agent


if __name__ == "__main__":
    from dotenv import load_dotenv
    load_dotenv("/opt/ai-server/.env")
    os.environ.setdefault("POSTGRES_HOST", "localhost")
    os.environ.setdefault("OLLAMA_BASE_URL", "http://localhost:11434")
    print("Social Media Agent - type 'quit' to exit\n")
    agent = create_social_media_agent()
    while True:
        user_input = input("You: ").strip()
        if not user_input: continue
        if user_input.lower() == 'quit': break
        try:
            print(f"\n{agent.name}: {agent.process_message(user_input)}\n")
        except Exception as e:
            print(f"Error: {e}\n")
