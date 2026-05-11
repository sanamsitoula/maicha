# Maicha — AI Automation Platform

Self-hosted AI automation server with specialist agents, dynamic model management, workflow automation, and multi-channel notifications.

## Architecture

```
┌─────────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│   Maicha UI │────▶│  Nginx   │────▶│ FastAPI  │────▶│  Ollama  │
│  (Browser)  │     │ :80      │     │ :8000    │     │ :11434   │
└─────────────┘     └──────────┘     └────┬─────┘     └──────────┘
                                          │
              ┌───────────────────────────┬┴──────────────────────┐
              ▼               ▼           ▼            ▼          ▼
        ┌──────────┐   ┌──────────┐ ┌──────────┐ ┌────────┐ ┌────────┐
        │PostgreSQL│   │  Qdrant  │ │   n8n    │ │Telegram│ │ Slack  │
        │ :5432    │   │  :6333   │ │  :5678   │ │  Bot   │ │Discord │
        └──────────┘   └──────────┘ └──────────┘ └────────┘ └────────┘
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

| Provider | Type | Models |
|----------|------|--------|
| Ollama | Local (free) | Any model from ollama.com/library |
| OpenAI | Paid API | gpt-4o, gpt-4o-mini, gpt-3.5-turbo |
| Anthropic | Paid API | claude-sonnet-4-20250514, claude-haiku-4-5-20251001 |
| DeepSeek | Paid API | deepseek-chat, deepseek-coder |
| Kimi | Paid API | moonshot-v1-8k, moonshot-v1-32k |

## Settings & Notifications

Configure communication channels from the API or UI:

### SMTP (Email)
```bash
POST /settings/smtp
{"host": "smtp.gmail.com", "port": 587, "username": "you@gmail.com",
 "password": "app-password", "from_email": "you@gmail.com", "use_tls": true}

POST /settings/smtp/test    # Test connection
POST /notify/email           # Send email
```

### Telegram
```bash
POST /settings/telegram
{"bot_token": "123456:ABC-DEF", "default_chat_id": "-100123456"}

POST /settings/telegram/test   # Test bot
POST /notify/telegram           # Send message
```

### Slack
```bash
POST /settings/slack
{"webhook_url": "https://hooks.slack.com/services/T.../B.../xxx"}

POST /settings/slack/test    # Test (sends a message)
POST /notify/slack           # Send message
```

### Discord
```bash
POST /settings/discord
{"webhook_url": "https://discord.com/api/webhooks/..."}

POST /settings/discord/test  # Test (sends a message)
POST /notify/discord         # Send message
```


### WhatsApp (Business API)
```bash
# Requires Meta Business account + WhatsApp Business API setup
# Get credentials from https://developers.facebook.com/

POST /settings/whatsapp
{"phone_number_id": "1234567890", "access_token": "EAAx...", "verify_token": "my-verify-token"}

POST /settings/whatsapp/test   # Test API connection
POST /notify/whatsapp           # Send message
{"to_phone": "9779812345678", "message": "Hello from Maicha!"}
```

### Send to All Channels
```bash
POST /notify/all
{"message": "New order received!", "channels": ["telegram", "slack", "discord"]}
```

## n8n Workflow Automation

| Workflow | Trigger | What It Does |
|----------|---------|--------------|
| Real Estate Lead Bot | Webhook | AI qualifies leads, sends follow-up emails |
| Restaurant Order Bot | Every 60s | Monitors orders, notifies kitchen |
| Social Media Content Bot | Daily 8AM | Generates multi-platform content |
| Marketing Email Bot | Weekdays 9AM | Creates newsletter content |

Access n8n: `http://YOUR_IP:5678`

## API Endpoints

### Core
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Maicha UI |
| GET | `/health` | Health check |
| POST | `/chat` | Chat with an agent |
| GET | `/docs` | Swagger API docs |

### Models
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/models` | List all models |
| POST | `/models/ollama/pull` | Pull Ollama model |
| POST | `/models/paid` | Add paid API model |
| POST | `/models/default` | Set default model |

### Settings
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/settings` | View all settings |
| POST | `/settings/smtp` | Configure SMTP |
| POST | `/settings/telegram` | Configure Telegram |
| POST | `/settings/slack` | Configure Slack |
| POST | `/settings/discord` | Configure Discord |
| POST | `/settings/whatsapp` | Configure WhatsApp |
| POST | `/settings/{channel}/test` | Test connection |

### Notifications
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/notify/email` | Send email |
| POST | `/notify/telegram` | Send Telegram |
| POST | `/notify/slack` | Send Slack |
| POST | `/notify/discord` | Send Discord |
| POST | `/notify/whatsapp` | Send WhatsApp |
| POST | `/notify/all` | Send to all channels |

### Data
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/menu` | Restaurant menu |
| GET | `/properties` | Property listings |
| GET | `/orders` | Orders |
| GET | `/stats` | Statistics |

## Services (9 containers)

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 5432 | Database |
| Qdrant | 6333 | Vector DB |
| Nginx | 80 | Proxy + UI |
| Ollama | 11434 | AI models |
| Open WebUI | 3000 | Chat UI |
| Adminer | 8080 | DB admin |
| FastAPI | 8000 | REST API |
| n8n | 5678 | Workflows |

## Project Structure

```
/opt/ai-server/
├── agents/
│   ├── api.py                      # FastAPI application
│   ├── shared/
│   │   ├── base_agent.py           # Base agent class
│   │   ├── database.py             # PostgreSQL helper
│   │   ├── ollama_client.py        # Unified LLM client
│   │   ├── model_manager.py        # Model registry
│   │   ├── settings_manager.py     # Platform settings
│   │   └── notification_sender.py  # Multi-channel notifications
│   ├── restaurant/agent.py
│   ├── real_estate/agent.py
│   ├── social_media/agent.py
│   ├── marketing/agent.py
│   ├── video/agent.py
│   └── orchestrator/agent.py
├── n8n/workflows/                  # Automation templates
├── nginx/
├── docker-compose.yml
└── .env.example
```


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

## Roadmap

- [x] Phase 1: Git repo + project structure
- [x] Phase 2: Dynamic model management
- [x] Phase 3: n8n automation engine
- [x] Phase 4: Settings panel (SMTP, Telegram, Slack, Discord)
- [x] Phase 5: Hermes agent + TranslateGemma (Nepali)
- [ ] Phase 6: Media pipeline (Stable Diffusion, TTS, Whisper)
- [ ] Phase 7: Social platform integration (Facebook, Instagram, TikTok)
- [ ] Phase 8: Maicha UI v2 (all features integrated)
