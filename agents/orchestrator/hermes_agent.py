"""
Hermes Agent — advanced multi-agent orchestrator using Hermes3.
Hermes3 excels at function calling and structured reasoning,
making it ideal for routing tasks between specialist agents.
"""
import os
import json
from agents.shared.base_agent import BaseAgent
from agents.shared.database import query, execute
from agents.shared.translator import translate_to_nepali, generate_nepali_content

HERMES_MODEL = os.getenv("HERMES_MODEL", "hermes3:latest")

SYSTEM_PROMPT = """You are Hermes, the master AI orchestrator for the Maicha platform.

You have access to specialist agents and tools. Your job is to:
1. Understand what the user needs
2. Route tasks to the right specialist agent
3. Coordinate multi-step workflows
4. Translate content to Nepali when requested
5. Combine outputs from multiple agents

Available agents: restaurant, real-estate, social-media, marketing, video

You can also translate content to Nepali using the translate tool, or generate
content directly in Nepali using the nepali_content tool.

Think step-by-step. If a task requires multiple agents, plan the workflow first,
then execute each step."""


def create_hermes_agent(model=None):
    agent = BaseAgent(
        name="Hermes Orchestrator",
        system_prompt=SYSTEM_PROMPT,
        model=model or HERMES_MODEL,
    )
    agent._conversation_id = None

    def _ensure_conversation():
        if agent._conversation_id is None:
            result = execute(
                "INSERT INTO conversations (agent_type, title, status) "
                "VALUES ('hermes', 'Hermes Chat', 'active') RETURNING id"
            )
            agent._conversation_id = result[0]["id"]
        return agent._conversation_id

    def _log_message(role, content, model_used=None):
        conv_id = _ensure_conversation()
        execute(
            "INSERT INTO messages (conversation_id, role, content, model_used) VALUES (%s, %s, %s, %s)",
            (conv_id, role, content, model_used)
        )

    def _log_event(event_type, data=None):
        execute(
            "INSERT INTO events (event_type, source, data) VALUES (%s, 'hermes-agent', %s)",
            (event_type, json.dumps(data or {}))
        )

    original_process = agent.process_message
    def logged_process_message(user_message):
        _log_message("user", user_message)
        response = original_process(user_message)
        _log_message("assistant", response, model_used=agent.model or HERMES_MODEL)
        return response
    agent.process_message = logged_process_message

    def logged_reset():
        agent.conversation_history = []
        agent._conversation_id = None
    agent.reset_conversation = logged_reset

    # ── Tool: Route to specialist agent ──
    def route_to_agent(agent_name, message):
        """Send a task to a specialist agent."""
        agent_factories = {
            "restaurant": ("agents.restaurant.agent", "create_restaurant_agent"),
            "real-estate": ("agents.real_estate.agent", "create_real_estate_agent"),
            "social-media": ("agents.social_media.agent", "create_social_media_agent"),
            "marketing": ("agents.marketing.agent", "create_marketing_agent"),
            "video": ("agents.video.agent", "create_video_agent"),
        }
        if agent_name not in agent_factories:
            return {"error": f"Unknown agent: {agent_name}. Available: {', '.join(agent_factories.keys())}"}
        
        import importlib
        module_path, factory_name = agent_factories[agent_name]
        mod = importlib.import_module(module_path)
        factory = getattr(mod, factory_name)
        specialist = factory()
        
        _log_event("hermes_route", {"target": agent_name, "message": message[:100]})
        response = specialist.process_message(message)
        return {"agent": agent_name, "response": response}

    agent.register_tool(
        name="route_to_agent",
        description="Send a task to a specialist agent: restaurant, real-estate, social-media, marketing, or video.",
        parameters={
            "agent_name": "string - which agent to use",
            "message": "string - the task or question",
        },
        function=route_to_agent,
    )

    # ── Tool: Translate to Nepali ──
    def translate(text, target_lang="ne"):
        """Translate text to Nepali (or other languages)."""
        if target_lang == "ne":
            result = translate_to_nepali(text)
        else:
            from agents.shared.translator import translate as general_translate
            result = general_translate(text, target_lang=target_lang)
        _log_event("translation", {"target_lang": target_lang, "text_length": len(text)})
        return result

    agent.register_tool(
        name="translate",
        description="Translate text to Nepali or other languages. Default target is Nepali (ne).",
        parameters={
            "text": "string - text to translate",
            "target_lang": "optional string - target language code (default: ne for Nepali)",
        },
        function=translate,
    )

    # ── Tool: Generate Nepali content ──
    def nepali_content(topic, content_type="post", platform="facebook"):
        """Generate social media content in Nepali."""
        result = generate_nepali_content(topic, content_type, platform)
        _log_event("nepali_content", {"topic": topic, "platform": platform})
        return result

    agent.register_tool(
        name="nepali_content",
        description="Generate social media content in both English and Nepali. Specify topic, content type, and platform.",
        parameters={
            "topic": "string - content topic",
            "content_type": "optional string - post, caption, article, ad (default: post)",
            "platform": "optional string - facebook, instagram, tiktok (default: facebook)",
        },
        function=nepali_content,
    )

    # ── Tool: Send notification ──
    def notify(message, channels=None):
        """Send a notification via configured channels."""
        from agents.shared.notification_sender import send_notification
        result = send_notification(message, channels)
        _log_event("notification_sent", {"channels": channels})
        return result

    agent.register_tool(
        name="notify",
        description="Send a notification via Telegram, Slack, Discord, or all channels.",
        parameters={
            "message": "string - notification message",
            "channels": "optional list - telegram, slack, discord (default: all configured)",
        },
        function=notify,
    )

    return agent


if __name__ == "__main__":
    from dotenv import load_dotenv
    load_dotenv("/opt/ai-server/.env")
    os.environ.setdefault("POSTGRES_HOST", "localhost")
    os.environ.setdefault("OLLAMA_BASE_URL", "http://localhost:11434")
    print("Hermes Orchestrator - type 'quit' to exit\n")
    agent = create_hermes_agent()
    while True:
        user_input = input("You: ").strip()
        if not user_input: continue
        if user_input.lower() == 'quit': break
        try:
            print(f"\n{agent.name}: {agent.process_message(user_input)}\n")
        except Exception as e:
            print(f"Error: {e}\n")
