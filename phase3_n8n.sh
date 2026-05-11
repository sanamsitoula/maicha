#!/bin/bash
set -e
echo "=== Phase 3: n8n Automation Engine ==="

BASE="/opt/ai-server"
cd "$BASE"

# ============================================
# Step 1: Add n8n to docker-compose.yml
# ============================================
if ! grep -q "ai-n8n" docker-compose.yml; then
cat >> docker-compose.yml << 'EOF'

  # ----- n8n: Workflow Automation Engine -----
  n8n:
    image: n8nio/n8n:latest
    container_name: ai-n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=http://20.41.122.188:5678/
      - GENERIC_TIMEZONE=${TIMEZONE}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ./n8n/data:/home/node/.n8n
    depends_on:
      - postgres
EOF
echo "Added n8n to docker-compose.yml"
else
echo "n8n already in docker-compose.yml"
fi

# ============================================
# Step 2: Create n8n database in PostgreSQL
# ============================================
echo "Creating n8n database..."
docker exec -i ai-postgres psql -U aiserver -d aiserver_db -c "
SELECT 'CREATE DATABASE n8n OWNER aiserver' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')
\gexec
" 2>/dev/null || docker exec -i ai-postgres psql -U aiserver -c "CREATE DATABASE n8n OWNER aiserver;" 2>/dev/null || echo "n8n database may already exist"

# ============================================
# Step 3: Ensure n8n data directory exists
# ============================================
mkdir -p "$BASE/n8n/data"

# ============================================
# Step 4: Add n8n proxy to Nginx config
# ============================================
# We'll add n8n routes. First check current nginx.conf
if ! grep -q "n8n" "$BASE/nginx/nginx.conf"; then
    # Insert n8n location before the last closing braces
    sed -i '/location \/openapi.json/a\
\
        location /n8n/ {\
            proxy_pass http://n8n:5678/;\
            proxy_set_header Host $host;\
            proxy_set_header Upgrade $http_upgrade;\
            proxy_set_header Connection "upgrade";\
            proxy_read_timeout 300s;\
        }' "$BASE/nginx/nginx.conf"
    echo "Added n8n proxy to nginx.conf"
else
    echo "n8n already in nginx.conf"
fi

# ============================================
# Step 5: Open port 5678 in firewall
# ============================================
sudo ufw allow 5678/tcp 2>/dev/null || true
echo "Opened port 5678"

# ============================================
# Step 6: Create n8n workflow templates as JSON
# ============================================
mkdir -p "$BASE/n8n/workflows"

# Workflow 1: Real Estate Lead Bot
cat > "$BASE/n8n/workflows/real_estate_lead_bot.json" << 'WFEOF'
{
  "name": "Real Estate Lead Bot",
  "description": "When a new property inquiry comes in, AI qualifies the lead and sends a follow-up email",
  "nodes_description": [
    "1. Webhook trigger: receives new inquiry from Maicha API",
    "2. HTTP Request: calls /chat with real-estate agent to qualify lead",
    "3. IF node: checks lead_score > 50",
    "4. High score path: sends personalized follow-up email via SMTP",
    "5. Low score path: logs to database for manual review",
    "6. Always: updates inquiry status in PostgreSQL"
  ],
  "setup_instructions": [
    "1. Open n8n at http://YOUR_IP:5678",
    "2. Create new workflow",
    "3. Add Webhook node (POST /webhook/real-estate-lead)",
    "4. Add HTTP Request node → POST http://ai-fastapi:8000/chat",
    "   Body: {\"message\": \"Qualify this lead: {{$json.contact_name}} interested in {{$json.property_title}}\", \"agent_type\": \"real-estate\"}",
    "5. Add IF node → check if response contains 'high priority' or 'qualified'",
    "6. True path: Add Send Email node (configure SMTP in Settings phase)",
    "7. False path: Add Postgres node → INSERT into events table",
    "8. Activate workflow"
  ],
  "webhook_endpoint": "/webhook/real-estate-lead",
  "api_calls": [
    {"method": "POST", "url": "http://ai-fastapi:8000/chat", "body": {"message": "Qualify this lead: {contact_name} asking about {property_title}. Their message: {message}", "agent_type": "real-estate"}}
  ]
}
WFEOF

# Workflow 2: Restaurant Order Notification Bot
cat > "$BASE/n8n/workflows/restaurant_order_bot.json" << 'WFEOF'
{
  "name": "Restaurant Order Notification Bot",
  "description": "Monitors new orders and sends notifications to kitchen + customer",
  "nodes_description": [
    "1. Schedule trigger: polls every 60 seconds",
    "2. HTTP Request: GET /orders?status=confirmed",
    "3. IF node: checks if new orders exist",
    "4. For each order: sends Telegram/Slack notification to kitchen",
    "5. Updates order status to 'preparing' via PostgreSQL",
    "6. Sends confirmation message to customer (if email provided)"
  ],
  "setup_instructions": [
    "1. Open n8n at http://YOUR_IP:5678",
    "2. Create new workflow",
    "3. Add Schedule Trigger node (every 1 minute)",
    "4. Add HTTP Request node → GET http://ai-fastapi:8000/orders?status=confirmed",
    "5. Add IF node → {{$json.count}} > 0",
    "6. True path: Add SplitInBatches for each order",
    "7. Add Telegram/Slack node (configure in Settings phase)",
    "8. Add Postgres node → UPDATE orders SET status='preparing' WHERE id={{$json.id}}",
    "9. Activate workflow"
  ],
  "webhook_endpoint": null,
  "api_calls": [
    {"method": "GET", "url": "http://ai-fastapi:8000/orders?status=confirmed"}
  ]
}
WFEOF

# Workflow 3: Social Media Content Generator Bot
cat > "$BASE/n8n/workflows/social_media_content_bot.json" << 'WFEOF'
{
  "name": "Social Media Content Generator Bot",
  "description": "Daily automated content generation + scheduling for all platforms",
  "nodes_description": [
    "1. Cron trigger: 8:00 AM daily",
    "2. HTTP Request: calls /chat with social-media agent for Instagram post",
    "3. HTTP Request: calls /chat with social-media agent for TikTok caption",
    "4. HTTP Request: calls /chat with social-media agent for Facebook post",
    "5. Stores all generated content in content_queue table",
    "6. Optional: posts directly via platform APIs (Phase 7)"
  ],
  "setup_instructions": [
    "1. Open n8n at http://YOUR_IP:5678",
    "2. Create new workflow",
    "3. Add Cron node (8:00 AM daily)",
    "4. Add HTTP Request → POST http://ai-fastapi:8000/chat",
    "   Body: {\"message\": \"Create an Instagram post about today's food trends. Include caption and 10 hashtags.\", \"agent_type\": \"social-media\"}",
    "5. Add another HTTP Request for TikTok:",
    "   Body: {\"message\": \"Write a TikTok caption about food delivery with trending hashtags\", \"agent_type\": \"social-media\"}",
    "6. Add another HTTP Request for Facebook:",
    "   Body: {\"message\": \"Write a Facebook post promoting our restaurant specials\", \"agent_type\": \"social-media\"}",
    "7. Add Postgres node to store each in content_queue table",
    "8. Activate workflow"
  ],
  "webhook_endpoint": null,
  "api_calls": [
    {"method": "POST", "url": "http://ai-fastapi:8000/chat", "body": {"message": "Create an Instagram post about today's food trends", "agent_type": "social-media"}},
    {"method": "POST", "url": "http://ai-fastapi:8000/chat", "body": {"message": "Write a TikTok caption about food delivery", "agent_type": "social-media"}},
    {"method": "POST", "url": "http://ai-fastapi:8000/chat", "body": {"message": "Write a Facebook post promoting restaurant specials", "agent_type": "social-media"}}
  ]
}
WFEOF

# Workflow 4: Daily Marketing Email Generator
cat > "$BASE/n8n/workflows/marketing_email_bot.json" << 'WFEOF'
{
  "name": "Daily Marketing Email Generator",
  "description": "Generates and stores marketing email campaigns using the marketing agent",
  "nodes_description": [
    "1. Cron trigger: 9:00 AM weekdays",
    "2. HTTP Request: calls /chat with marketing agent",
    "3. Parses response for subject line + body",
    "4. Stores in agent_memory table",
    "5. Optional: sends via SMTP (Phase 4)"
  ],
  "setup_instructions": [
    "1. Open n8n at http://YOUR_IP:5678",
    "2. Create new workflow",
    "3. Add Cron node (9:00 AM, Mon-Fri)",
    "4. Add HTTP Request → POST http://ai-fastapi:8000/chat",
    "   Body: {\"message\": \"Write a marketing email for our weekly restaurant newsletter. Include subject line, preview text, and body.\", \"agent_type\": \"marketing\"}",
    "5. Add Postgres node → INSERT into agent_memory",
    "6. Activate workflow"
  ],
  "webhook_endpoint": null,
  "api_calls": [
    {"method": "POST", "url": "http://ai-fastapi:8000/chat", "body": {"message": "Write a marketing email for our weekly newsletter", "agent_type": "marketing"}}
  ]
}
WFEOF

echo "Created 4 n8n workflow templates"

# ============================================
# Step 7: Add n8n workflow API endpoints to FastAPI
# ============================================
# Append n8n-related routes to api.py
cat >> "$BASE/agents/api.py" << 'PYEOF'


# ── n8n Integration Routes ──

@app.get("/n8n/workflows")
def list_n8n_workflows():
    """List available n8n workflow templates."""
    import glob
    workflows = []
    for f in sorted(glob.glob("/app/agents/../n8n/workflows/*.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
                workflows.append({
                    "file": f.split("/")[-1],
                    "name": data.get("name", "Unknown"),
                    "description": data.get("description", ""),
                })
        except Exception:
            pass

    # Also try the mounted path
    for f in sorted(glob.glob("/opt/ai-server/n8n/workflows/*.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
                name = data.get("name", "Unknown")
                if not any(w["name"] == name for w in workflows):
                    workflows.append({
                        "file": f.split("/")[-1],
                        "name": name,
                        "description": data.get("description", ""),
                    })
        except Exception:
            pass

    return {
        "workflows": workflows,
        "n8n_url": "http://20.41.122.188:5678",
        "n8n_status": _check_n8n_status(),
    }


def _check_n8n_status():
    """Check if n8n is reachable."""
    try:
        resp = httpx.get("http://n8n:5678/healthz", timeout=3.0)
        return "running" if resp.status_code == 200 else "error"
    except Exception:
        return "unreachable"


@app.get("/n8n/workflow/{filename}")
def get_n8n_workflow(filename: str):
    """Get a specific workflow template."""
    import os.path
    for base_path in ["/opt/ai-server/n8n/workflows", "/app/agents/../n8n/workflows"]:
        filepath = os.path.join(base_path, filename)
        if os.path.exists(filepath):
            with open(filepath) as f:
                return json.load(f)
    raise HTTPException(status_code=404, detail=f"Workflow not found: {filename}")
PYEOF

echo "Added n8n endpoints to api.py"

# ============================================
# Step 8: Add httpx import if missing in api.py
# ============================================
if ! grep -q "^import httpx" "$BASE/agents/api.py"; then
    sed -i '1s/^/import httpx\n/' "$BASE/agents/api.py"
fi

# ============================================
# Step 9: Update Dockerfile to copy n8n workflow files
# ============================================
cat > "$BASE/agents/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . /app/agents/
ENV PYTHONPATH=/app
CMD ["python", "-m", "uvicorn", "agents.api:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# ============================================
# Step 10: Mount n8n workflows into fastapi container
# ============================================
if ! grep -q "n8n/workflows" docker-compose.yml; then
    sed -i '/container_name: ai-fastapi/,/depends_on:/{
        /depends_on:/i\
    volumes:\
      - ./n8n/workflows:/opt/ai-server/n8n/workflows:ro
    }' docker-compose.yml 2>/dev/null || true
fi

# ============================================
# Step 11: Update README.md
# ============================================
cat > README.md << 'READMEEOF'
# Maicha — AI Automation Platform

Self-hosted AI automation server with multiple specialist agents, dynamic model management, workflow automation via n8n, and support for both local and paid LLMs.

## Architecture

```
┌─────────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│   Maicha UI │────▶│  Nginx   │────▶│ FastAPI  │────▶│  Ollama  │
│  (Browser)  │     │ :80      │     │ :8000    │     │ :11434   │
└─────────────┘     └──────────┘     └────┬─────┘     └──────────┘
                                          │
                         ┌────────────────┼────────────────┐
                         ▼                ▼                ▼
                   ┌──────────┐    ┌──────────┐     ┌──────────┐
                   │PostgreSQL│    │  Qdrant  │     │   n8n    │
                   │ :5432    │    │  :6333   │     │  :5678   │
                   └──────────┘    └──────────┘     └──────────┘
```

## AI Agents

| Agent | Description |
|-------|-------------|
| Restaurant | Menu queries, food orders, reservations |
| Real Estate | Property search, inquiries, lead qualification |
| Social Media | Content generation, hashtags, scheduling |
| Marketing | Ad copy, email campaigns, blog posts |
| Video | Script generation, media jobs, render queue |
| Orchestrator | Routes tasks to the right specialist agent |

## Model Management

Supports dynamic model management — add, remove, and switch models at runtime.

### Supported Providers

| Provider | Type | Models |
|----------|------|--------|
| Ollama | Local (free) | llama3.2, qwen3, phi3, mistral, deepseek-coder, translategemma, any Ollama model |
| OpenAI | Paid API | gpt-4o, gpt-4o-mini, gpt-3.5-turbo |
| Anthropic | Paid API | claude-sonnet-4-20250514, claude-haiku-4-5-20251001 |
| DeepSeek | Paid API | deepseek-chat, deepseek-coder |
| Kimi | Paid API | moonshot-v1-8k, moonshot-v1-32k |

## n8n Workflow Automation

Pre-built workflow templates for automating AI-powered tasks:

| Workflow | Trigger | What It Does |
|----------|---------|--------------|
| Real Estate Lead Bot | Webhook | Qualifies leads via AI, sends follow-up emails |
| Restaurant Order Bot | Every 60s | Monitors orders, notifies kitchen via Telegram/Slack |
| Social Media Content Bot | Daily 8AM | Generates posts for Instagram, TikTok, Facebook |
| Marketing Email Bot | Weekdays 9AM | Creates newsletter content via marketing agent |

### n8n Setup

```bash
# Access n8n
http://YOUR_IP:5678

# Default credentials (from .env)
User: admin
Password: (your N8N_BASIC_AUTH_PASSWORD)

# n8n connects to Maicha via internal Docker network:
# API base: http://ai-fastapi:8000
# Example: POST http://ai-fastapi:8000/chat
```

### Workflow Templates

Templates are in `/n8n/workflows/`. Each JSON file contains:
- Node descriptions (what each step does)
- Setup instructions (step-by-step guide)
- API call examples (exact HTTP requests to configure)

## API Endpoints

### Core

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Maicha UI |
| GET | `/health` | Health check |
| GET | `/agents` | List all agents |
| POST | `/chat` | Chat with an agent (accepts optional `model` field) |
| GET | `/docs` | Swagger API docs |

### Data

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/menu` | Restaurant menu |
| GET | `/properties` | Property listings |
| GET | `/orders` | View orders |
| GET | `/conversations` | Conversation history |
| GET | `/events` | Analytics events |
| GET | `/stats` | System statistics |

### Model Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/models` | List all models + providers |
| POST | `/models/ollama/pull` | Pull new Ollama model |
| DELETE | `/models/ollama/{name}` | Delete Ollama model |
| POST | `/models/paid` | Add paid API model |
| POST | `/models/default` | Set default model |

### n8n Integration

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/n8n/workflows` | List workflow templates + n8n status |
| GET | `/n8n/workflow/{file}` | Get specific workflow template |

## Services

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| PostgreSQL | ai-postgres | 5432 | Main database |
| Qdrant | ai-qdrant | 6333 | Vector database |
| Nginx | ai-nginx | 80 | Reverse proxy + UI |
| Ollama | ai-ollama | 11434 | Local AI models |
| Open WebUI | ai-open-webui | 3000 | Chat interface |
| Adminer | ai-adminer | 8080 | Database management |
| FastAPI | ai-fastapi | 8000 | REST API |
| n8n | ai-n8n | 5678 | Workflow automation |

## Project Structure

```
/opt/ai-server/
├── agents/                     # Python agent code
│   ├── __init__.py
│   ├── api.py                  # FastAPI application
│   ├── shared/
│   │   ├── base_agent.py       # Base agent class
│   │   ├── database.py         # PostgreSQL helper
│   │   ├── ollama_client.py    # Unified LLM client
│   │   └── model_manager.py    # Dynamic model registry
│   ├── restaurant/agent.py
│   ├── real_estate/agent.py
│   ├── social_media/agent.py
│   ├── marketing/agent.py
│   ├── video/agent.py
│   └── orchestrator/agent.py
├── n8n/
│   ├── data/                   # n8n runtime data (gitignored)
│   └── workflows/              # Workflow templates
│       ├── real_estate_lead_bot.json
│       ├── restaurant_order_bot.json
│       ├── social_media_content_bot.json
│       └── marketing_email_bot.json
├── nginx/
│   ├── nginx.conf
│   └── maicha.html
├── postgres/
│   └── init-schema.sql
├── docker-compose.yml
├── .env
└── .env.example
```

## Development

```bash
# Clone
git clone https://github.com/sanamsitoula/maicha.git
cd maicha

# Configure
cp .env.example .env
# Edit .env

# Start
docker compose up -d

# Rebuild after changes
docker compose build fastapi
docker compose up -d

# Logs
docker logs ai-fastapi --tail 50 -f
docker logs ai-n8n --tail 50 -f
```

## Roadmap

- [x] Phase 1: Git repo + project structure
- [x] Phase 2: Dynamic model management (Ollama + paid APIs)
- [x] Phase 3: n8n automation engine + workflow bots
- [ ] Phase 4: Settings panel (SMTP, Telegram, Slack, Discord)
- [ ] Phase 5: Hermes agent + TranslateGemma (Nepali)
- [ ] Phase 6: Media pipeline (Stable Diffusion, TTS, Whisper)
- [ ] Phase 7: Social platform integration (Facebook, Instagram, TikTok)
- [ ] Phase 8: Maicha UI v2 (all features integrated)
READMEEOF

echo "Updated README.md"

# ============================================
# Step 12: Git commit
# ============================================
git add -A
git commit -m "Phase 3: n8n automation engine + workflow bots

Features:
- n8n container added to docker-compose (port 5678)
- n8n uses PostgreSQL as backend database
- 4 pre-built workflow templates:
  * Real Estate Lead Bot (webhook → AI qualification → email)
  * Restaurant Order Bot (polling → kitchen notification)
  * Social Media Content Bot (daily cron → multi-platform content)
  * Marketing Email Bot (weekday cron → newsletter generation)
- FastAPI endpoints: /n8n/workflows, /n8n/workflow/{file}
- n8n proxy added to nginx config
- Workflow templates stored as JSON with setup instructions
- README updated with n8n docs + architecture diagram"

echo ""
echo "=== Phase 3 Complete ==="
echo ""
echo "Run these commands:"
echo "  cd /opt/ai-server"
echo "  docker compose build fastapi"
echo "  docker compose up -d"
echo "  git push"
echo ""
echo "Then open port 5678 in Azure NSG:"
echo "  Portal → VM → Networking → Add inbound rule → port 5678, TCP, Allow"
echo ""
echo "Access n8n at: http://20.41.122.188:5678"
echo "  User: admin"
echo "  Password: (your N8N_BASIC_AUTH_PASSWORD from .env)"
echo ""
echo "Test API:"
echo "  curl http://localhost:8000/n8n/workflows"
echo ""
echo "To build workflows in n8n:"
echo "  1. Open n8n in browser"
echo "  2. Create New Workflow"
echo "  3. Follow the setup_instructions in each template JSON"
echo "  4. Use http://ai-fastapi:8000 as the API base (internal Docker network)"
