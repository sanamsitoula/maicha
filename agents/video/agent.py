import os
import json
from agents.shared.base_agent import BaseAgent
from agents.shared.database import query, execute

SYSTEM_PROMPT = """You are a video content creation specialist.

Your responsibilities:
1. Generate video scripts for YouTube, TikTok, and Instagram Reels
2. Create media generation jobs
3. Manage the render queue
4. Adapt script length to target platform

Write scripts that are engaging from the first second. Include [VISUAL] cues and [VOICEOVER] text."""


def create_video_agent(model=None):
    agent = BaseAgent(name="Video Agent", system_prompt=SYSTEM_PROMPT, model=model)
    agent._conversation_id = None

    def _ensure_conversation():
        if agent._conversation_id is None:
            result = execute(
                "INSERT INTO conversations (agent_type, title, status) "
                "VALUES ('video', 'Video Production Chat', 'active') RETURNING id"
            )
            agent._conversation_id = result[0]["id"]
        return agent._conversation_id

    def _log_message(role, content, model_used=None):
        conv_id = _ensure_conversation()
        execute("INSERT INTO messages (conversation_id, role, content, model_used) VALUES (%s, %s, %s, %s)",
                (conv_id, role, content, model_used))

    def _log_event(event_type, data=None):
        execute("INSERT INTO events (event_type, source, data) VALUES (%s, 'video-agent', %s)",
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

    def create_script(topic, platform, duration_seconds=60):
        result = execute(
            "INSERT INTO generated_scripts (topic, target_platform, target_duration_seconds, script_text, model_used, status) "
            "VALUES (%s, %s, %s, 'pending', %s, 'draft') RETURNING id",
            (topic, platform, duration_seconds, os.getenv("DEFAULT_MODEL", "llama3.2:3b"))
        )
        _log_event("script_created", {"topic": topic, "platform": platform})
        return {
            "script_id": str(result[0]["id"]), "topic": topic, "platform": platform,
            "instruction": f"Write a {duration_seconds}-second video script for {platform} about: {topic}. Include [VISUAL] cues and [VOICEOVER] text."
        }

    agent.register_tool(
        name="create_script",
        description="Create a new video script.",
        parameters={
            "topic": "string", "platform": "string - youtube, tiktok, instagram",
            "duration_seconds": "optional integer (default 60)",
        },
        function=create_script,
    )

    def save_script(script_id, script_text):
        execute("UPDATE generated_scripts SET script_text = %s, status = 'completed' WHERE id = %s::uuid",
                (script_text, script_id))
        return {"status": "saved", "script_id": script_id}

    agent.register_tool(
        name="save_script",
        description="Save the final script text.",
        parameters={"script_id": "string - UUID", "script_text": "string - the complete script"},
        function=save_script,
    )

    def create_media_job(job_type, input_data):
        result = execute(
            "INSERT INTO media_jobs (job_type, input_data, status) VALUES (%s, %s, 'queued') RETURNING id",
            (job_type, json.dumps(input_data))
        )
        _log_event("media_job_created", {"job_type": job_type})
        return {"job_id": str(result[0]["id"]), "job_type": job_type, "status": "queued"}

    agent.register_tool(
        name="create_media_job",
        description="Create a media generation job (voiceover, image, video).",
        parameters={"job_type": "string - video, image, audio, voiceover", "input_data": "dict - job parameters"},
        function=create_media_job,
    )

    return agent


if __name__ == "__main__":
    from dotenv import load_dotenv
    load_dotenv("/opt/ai-server/.env")
    os.environ.setdefault("POSTGRES_HOST", "localhost")
    os.environ.setdefault("OLLAMA_BASE_URL", "http://localhost:11434")
    print("Video Agent - type 'quit' to exit\n")
    agent = create_video_agent()
    while True:
        user_input = input("You: ").strip()
        if not user_input: continue
        if user_input.lower() == 'quit': break
        try:
            print(f"\n{agent.name}: {agent.process_message(user_input)}\n")
        except Exception as e:
            print(f"Error: {e}\n")
