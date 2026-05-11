import os
import json
from agents.shared.base_agent import BaseAgent
from agents.shared.database import query, execute
from agents.restaurant.agent import create_restaurant_agent
from agents.real_estate.agent import create_real_estate_agent
from agents.social_media.agent import create_social_media_agent
from agents.marketing.agent import create_marketing_agent
from agents.video.agent import create_video_agent

SYSTEM_PROMPT = """You are the AI Orchestrator - a master coordinator that routes requests to specialist agents.

You manage: Restaurant, Real Estate, Social Media, Marketing, and Video agents.
Use route_to_agent to send work to the right specialist."""


def create_orchestrator_agent(model=None):
    agent = BaseAgent(name="AI Orchestrator", system_prompt=SYSTEM_PROMPT, model=model)
    agent._conversation_id = None
    specialists = {
        "restaurant": create_restaurant_agent(model),
        "real-estate": create_real_estate_agent(model),
        "social-media": create_social_media_agent(model),
        "marketing": create_marketing_agent(model),
        "video": create_video_agent(model),
    }

    def _ensure_conversation():
        if agent._conversation_id is None:
            result = execute(
                "INSERT INTO conversations (agent_type, title, status) "
                "VALUES ('orchestrator', 'Orchestrator Chat', 'active') RETURNING id"
            )
            agent._conversation_id = result[0]["id"]
        return agent._conversation_id

    def _log_message(role, content, model_used=None):
        conv_id = _ensure_conversation()
        execute("INSERT INTO messages (conversation_id, role, content, model_used) VALUES (%s, %s, %s, %s)",
                (conv_id, role, content, model_used))

    def _log_event(event_type, data=None):
        execute("INSERT INTO events (event_type, source, data) VALUES (%s, 'orchestrator', %s)",
                (event_type, json.dumps(data or {})))

    original_process = agent.process_message
    def logged_process_message(user_message):
        _log_message("user", user_message)
        response = original_process(user_message)
        _log_message("assistant", response, model_used=agent.model or os.getenv("DEFAULT_MODEL", "llama3.2:3b"))
        return response
    agent.process_message = logged_process_message

    def route_to_agent(agent_name, message):
        if agent_name not in specialists:
            return {"error": f"Unknown agent: {agent_name}. Available: {', '.join(specialists.keys())}"}
        _log_event("task_routed", {"target_agent": agent_name})
        response = specialists[agent_name].process_message(message)
        return {"agent": agent_name, "response": response}

    agent.register_tool(
        name="route_to_agent",
        description="Send a task to a specialist agent.",
        parameters={
            "agent_name": "string - restaurant, real-estate, social-media, marketing, or video",
            "message": "string - the task for the specialist",
        },
        function=route_to_agent,
    )

    return agent
