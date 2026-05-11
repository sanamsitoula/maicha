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
