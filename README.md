# Maicha — AI Automation Platform

Self-hosted AI automation server with multiple specialist agents, powered by local LLMs via Ollama.

## Architecture

```
┌─────────────┐     ┌──────────┐     ┌──────────┐
│   Maicha UI │────▶│  Nginx   │────▶│ FastAPI  │
│  (Browser)  │     │ :80      │     │ :8000    │
└─────────────┘     └──────────┘     └────┬─────┘
                                          │
                    ┌─────────────────────┬┴────────────┐
                    ▼                     ▼              ▼
              ┌──────────┐        ┌──────────┐   ┌──────────┐
              │ Ollama   │        │PostgreSQL│   │  Qdrant  │
              │ :11434   │        │ :5432    │   │  :6333   │
              └──────────┘        └──────────┘   └──────────┘
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

## Quick Start

```bash
# Clone and configure
cp .env.example .env
# Edit .env with your passwords

# Start all services
docker compose up -d

# Check status
docker compose ps
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Maicha UI |
| GET | `/health` | Health check |
| GET | `/agents` | List all agents |
| POST | `/chat` | Chat with an agent |
| GET | `/menu` | Restaurant menu |
| GET | `/properties` | Property listings |
| GET | `/orders` | View orders |
| GET | `/stats` | System statistics |
| GET | `/docs` | Swagger API docs |

## Tech Stack

- **Runtime**: Python 3.11 + FastAPI
- **AI Models**: Ollama (llama3.2, phi3, etc.)
- **Database**: PostgreSQL 16 + Qdrant
- **Frontend**: React (Babel standalone)
- **Proxy**: Nginx
- **Container**: Docker Compose

## Project Structure

```
/opt/ai-server/
├── agents/                 # Python agent code
│   ├── api.py             # FastAPI application
│   ├── shared/            # Database, Ollama client, base agent
│   ├── restaurant/        # Restaurant ordering agent
│   ├── real_estate/       # Property listing agent
│   ├── social_media/      # Social content agent
│   ├── marketing/         # Marketing copy agent
│   ├── video/             # Video script agent
│   └── orchestrator/      # Multi-agent coordinator
├── nginx/                 # Nginx config + Maicha UI
├── postgres/              # DB schema
├── docker-compose.yml     # Service orchestration
└── .env                   # Secrets (not in repo)
```

## Development

```bash
# SSH into server
ssh -i key.pem azureuser@YOUR_IP

# Rebuild after code changes
docker compose build fastapi
docker compose up -d

# View logs
docker logs ai-fastapi --tail 50 -f

# Run agent tests
docker compose run --rm agent-runner python -c "
from agents.restaurant.agent import create_restaurant_agent
agent = create_restaurant_agent()
print(agent.process_message('What is on the menu?'))
"
```
