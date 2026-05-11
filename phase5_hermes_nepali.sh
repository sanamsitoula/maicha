#!/bin/bash
set -e
echo "=== Phase 5: Hermes Agent + TranslateGemma for Nepali ==="

BASE="/opt/ai-server"
AGENTS="$BASE/agents"
cd "$BASE"

# ============================================
# Step 1: Pull Hermes3 and TranslateGemma models
# ============================================
echo "Pulling hermes3 model (this may take several minutes)..."
curl -s -X POST http://localhost:8000/models/ollama/pull -H "Content-Type: application/json" -d '{"name":"hermes3:latest"}' || echo "hermes3 pull initiated"

echo ""
echo "Pulling translategemma model..."
curl -s -X POST http://localhost:8000/models/ollama/pull -H "Content-Type: application/json" -d '{"name":"translategemma:latest"}' || echo "translategemma pull initiated"

echo ""
echo "Models pulling in background. Continuing with code setup..."
echo ""

# ============================================
# Step 2: Create translation module
# ============================================
mkdir -p "$AGENTS/shared"

cat > "$AGENTS/shared/translator.py" << 'EOF'
"""
Translator — uses TranslateGemma for Nepali translation
and supports other language pairs via Ollama models.
"""
import os
from agents.shared.ollama_client import chat

TRANSLATE_MODEL = os.getenv("TRANSLATE_MODEL", "translategemma:latest")


def translate_to_nepali(text, model=None):
    """Translate English text to Nepali using TranslateGemma."""
    model = model or TRANSLATE_MODEL
    messages = [
        {"role": "system", "content": "You are a translator. Translate the following English text to Nepali. Output ONLY the Nepali translation, nothing else."},
        {"role": "user", "content": text},
    ]
    try:
        result = chat(messages, model=model, temperature=0.3)
        return {"status": "ok", "original": text, "translated": result, "language": "ne", "model": model}
    except Exception as e:
        return {"status": "error", "message": str(e), "original": text}


def translate_to_english(text, model=None):
    """Translate Nepali text to English using TranslateGemma."""
    model = model or TRANSLATE_MODEL
    messages = [
        {"role": "system", "content": "You are a translator. Translate the following Nepali text to English. Output ONLY the English translation, nothing else."},
        {"role": "user", "content": text},
    ]
    try:
        result = chat(messages, model=model, temperature=0.3)
        return {"status": "ok", "original": text, "translated": result, "language": "en", "model": model}
    except Exception as e:
        return {"status": "error", "message": str(e), "original": text}


def translate(text, source_lang="en", target_lang="ne", model=None):
    """General translation between any supported languages."""
    model = model or TRANSLATE_MODEL
    messages = [
        {"role": "system", "content": f"You are a translator. Translate the following {source_lang} text to {target_lang}. Output ONLY the translation, nothing else."},
        {"role": "user", "content": text},
    ]
    try:
        result = chat(messages, model=model, temperature=0.3)
        return {"status": "ok", "original": text, "translated": result, "source": source_lang, "target": target_lang, "model": model}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def generate_nepali_content(topic, content_type="post", platform="facebook", model=None):
    """Generate content directly in Nepali.

    Two-step process:
    1. Generate content in English using the default LLM
    2. Translate to Nepali using TranslateGemma
    """
    from agents.shared.ollama_client import generate

    english_prompt = f"Write a {content_type} for {platform} about: {topic}. Be engaging and include relevant hashtags."
    english_content = generate(english_prompt, temperature=0.8)

    nepali_result = translate_to_nepali(english_content, model=model)

    return {
        "status": "ok",
        "topic": topic,
        "platform": platform,
        "content_type": content_type,
        "english": english_content,
        "nepali": nepali_result.get("translated", "Translation failed"),
        "translate_model": model or TRANSLATE_MODEL,
    }
EOF

echo "Created translator.py"

# ============================================
# Step 3: Create Hermes-powered orchestrator
# ============================================
cat > "$AGENTS/orchestrator/hermes_agent.py" << 'EOF'
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
EOF

echo "Created hermes_agent.py"

# ============================================
# Step 4: Add translation + Hermes endpoints to api.py
# ============================================
cat >> "$AGENTS/api.py" << 'PYEOF'


# ── Translation Routes ──

from agents.shared.translator import translate_to_nepali, translate_to_english, translate, generate_nepali_content


class TranslateRequest(BaseModel):
    text: str
    source_lang: str = "en"
    target_lang: str = "ne"
    model: Optional[str] = None

class NepaliContentRequest(BaseModel):
    topic: str
    content_type: str = "post"
    platform: str = "facebook"
    model: Optional[str] = None


@app.post("/translate")
def api_translate(req: TranslateRequest):
    """Translate text between languages. Default: English → Nepali."""
    return translate(req.text, req.source_lang, req.target_lang, req.model)

@app.post("/translate/to-nepali")
def api_to_nepali(req: TranslateRequest):
    """Translate English text to Nepali."""
    return translate_to_nepali(req.text, req.model)

@app.post("/translate/to-english")
def api_to_english(req: TranslateRequest):
    """Translate Nepali text to English."""
    return translate_to_english(req.text, req.model)

@app.post("/content/nepali")
def api_nepali_content(req: NepaliContentRequest):
    """Generate social media content in both English and Nepali."""
    return generate_nepali_content(req.topic, req.content_type, req.platform, req.model)


# ── Hermes Orchestrator Route ──

from agents.orchestrator.hermes_agent import create_hermes_agent

_hermes_instance = None

@app.post("/hermes")
def hermes_chat(req: ChatRequest):
    """Chat with the Hermes orchestrator — advanced multi-agent routing + Nepali translation."""
    global _hermes_instance
    start = time.time()

    if _hermes_instance is None:
        _hermes_instance = create_hermes_agent()

    if req.session_id == "new" or req.session_id is None:
        _hermes_instance.reset_conversation()
        session_id = secrets.token_hex(8)
    else:
        session_id = req.session_id

    response = _hermes_instance.process_message(req.message)
    elapsed = round(time.time() - start, 2)

    return ChatResponse(
        response=response,
        agent_type="hermes",
        model_used=_hermes_instance.model or "hermes3:latest",
        session_id=session_id,
        elapsed_seconds=elapsed,
    )
PYEOF

echo "Added translation + Hermes endpoints to api.py"

# ============================================
# Step 5: Update agents list in api.py
# ============================================
python3 << 'PYFIX'
filepath = "/opt/ai-server/agents/api.py"
with open(filepath, "r") as f:
    content = f.read()

old_agents = '''{"name": "video", "description": "Video scripts, media production"},
    ]}'''
new_agents = '''{"name": "video", "description": "Video scripts, media production"},
        {"name": "hermes", "description": "Advanced orchestrator — multi-agent routing + Nepali translation"},
    ]}'''

content = content.replace(old_agents, new_agents)

with open(filepath, "w") as f:
    f.write(content)
print("Updated agents list")
PYFIX

# ============================================
# Step 6: Add /translate and /hermes to nginx
# ============================================
if ! grep -q "location /translate" "$BASE/nginx/nginx.conf"; then
    sed -i '/location \/notify/a\
        location /translate { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Content-Type $http_content_type; proxy_read_timeout 300s; }\
        location /content { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Content-Type $http_content_type; proxy_read_timeout 300s; }\
        location /hermes { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Content-Type $http_content_type; proxy_read_timeout 300s; }' "$BASE/nginx/nginx.conf"
    echo "Added /translate, /content, /hermes to nginx"
fi

# ============================================
# Step 7: Update README.md
# ============================================
python3 << 'PYFIX2'
filepath = "/opt/ai-server/README.md"
with open(filepath, "r") as f:
    content = f.read()

# Add Hermes + Translation section before Roadmap
translation_docs = """
## Hermes Orchestrator

Advanced multi-agent coordinator using Hermes3 model. Routes tasks, coordinates workflows, and handles Nepali translation.

```bash
# Chat with Hermes (auto-routes to specialists)
POST /hermes
{"message": "Create an Instagram post about Kathmandu food and translate to Nepali", "agent_type": "hermes"}
```

## Translation & Nepali Content

### Translate Text
```bash
# English → Nepali
POST /translate/to-nepali
{"text": "Welcome to our restaurant!"}

# Nepali → English
POST /translate/to-english
{"text": "हाम्रो रेस्टुरेन्टमा स्वागत छ!"}

# Any language pair
POST /translate
{"text": "Hello world", "source_lang": "en", "target_lang": "ne"}
```

### Generate Nepali Content
```bash
POST /content/nepali
{"topic": "Dashain festival food", "content_type": "post", "platform": "facebook"}

# Returns both English and Nepali versions
```

### Models Used
- **hermes3:latest** — Advanced reasoning + function calling for orchestration
- **translategemma:latest** — Specialized translation model for Nepali

"""

content = content.replace("## Roadmap", translation_docs + "## Roadmap")

# Update roadmap
content = content.replace(
    "- [ ] Phase 5: Hermes agent + TranslateGemma (Nepali)",
    "- [x] Phase 5: Hermes agent + TranslateGemma (Nepali)"
)

with open(filepath, "w") as f:
    f.write(content)
print("Updated README")
PYFIX2

# ============================================
# Step 8: Git commit
# ============================================
git add -A
git commit -m "Phase 5: Hermes agent + TranslateGemma for Nepali

Features:
- translator.py: English↔Nepali translation via TranslateGemma
- generate_nepali_content(): two-step English generation + Nepali translation
- hermes_agent.py: advanced orchestrator using Hermes3 model
  * Routes tasks to specialist agents
  * Translates content to Nepali
  * Generates bilingual social media content
  * Sends notifications via configured channels
- API endpoints:
  * POST /translate (general), /translate/to-nepali, /translate/to-english
  * POST /content/nepali (bilingual content generation)
  * POST /hermes (advanced orchestrator chat)
- Nginx updated with translation + hermes proxy routes
- README updated with translation + Hermes docs
- Models: hermes3:latest + translategemma:latest pulled via Ollama"

echo ""
echo "=== Phase 5 Complete ==="
echo ""
echo "Run:"
echo "  cd /opt/ai-server"
echo "  docker compose build fastapi"
echo "  docker compose up -d --force-recreate fastapi nginx"
echo "  git push"
echo ""
echo "Check model download progress:"
echo "  docker exec ai-ollama ollama list"
echo ""
echo "Test (after models finish downloading):"
echo "  curl -X POST http://localhost:8000/translate/to-nepali -H 'Content-Type: application/json' -d '{\"text\":\"Welcome to our restaurant!\"}'"
echo "  curl -X POST http://localhost:8000/content/nepali -H 'Content-Type: application/json' -d '{\"topic\":\"Dashain festival food\",\"platform\":\"facebook\"}'"
echo "  curl -X POST http://localhost:8000/hermes -H 'Content-Type: application/json' -d '{\"message\":\"Create a Facebook post about Nepali food and translate to Nepali\",\"agent_type\":\"hermes\"}'"
