#!/bin/bash
set -e
echo "=== Phase 1: Git Repo + Project Restructure ==="
echo ""

cd /opt/ai-server

# ============================================
# Step 1: Create .gitignore
# ============================================
cat > .gitignore << 'EOF'
# Environment & secrets
.env
*.env.local
*.env.production

# Database data
postgres/data/
qdrant/data/

# Ollama models (large binary files)
ollama/data/

# Open WebUI data
open-webui/data/

# Python
__pycache__/
*.pyc
*.pyo
*.egg-info/
dist/
build/
.eggs/
*.egg
.venv/
venv/

# Docker
*.log

# OS files
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# Backups
backups/*.sql
backups/*.gz

# Deploy scripts (one-time use)
deploy_*.sh
fix_*.sh
EOF

echo "Created .gitignore"

# ============================================
# Step 2: Create .env.example (safe to commit)
# ============================================
cat > .env.example << 'EOF'
# ============================================
# AI Server Environment Variables
# Copy this to .env and fill in real values
# ============================================

# PostgreSQL Database
POSTGRES_USER=aiserver
POSTGRES_PASSWORD=CHANGE_ME
POSTGRES_DB=aiserver_db

# Qdrant Vector Database
QDRANT_API_KEY=CHANGE_ME

# n8n Automation
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=CHANGE_ME

# FastAPI
API_KEY=CHANGE_ME

# General
DOMAIN=localhost
TIMEZONE=UTC
EOF

echo "Created .env.example"

# ============================================
# Step 3: Create proper Python package structure
# ============================================

# Add __init__.py to orchestrator if missing
touch agents/orchestrator/__init__.py
touch agents/video/__init__.py

# Create a top-level agents __init__.py that exports all factories
cat > agents/__init__.py << 'EOF'
"""
Maicha AI Agents — top-level package
"""
__version__ = "1.0.0"
EOF

echo "Fixed Python package structure"

# ============================================
# Step 4: Create README.md
# ============================================
cat > README.md << 'EOF'
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
EOF

echo "Created README.md"

# ============================================
# Step 5: Initialize Git repo
# ============================================
git init
git add .gitignore
git add .env.example
git add README.md
git add docker-compose.yml
git add agents/
git add nginx/nginx.conf
git add nginx/maicha.html
git add postgres/init-schema.sql 2>/dev/null || true

echo ""
echo "Files staged for first commit:"
git status --short
echo ""

git config user.email "azureuser@ai-module"
git config user.name "Maicha Developer"

git commit -m "Initial commit: Maicha AI Automation Platform

- 6 AI agents (restaurant, real estate, social media, marketing, video, orchestrator)
- FastAPI backend with REST API
- PostgreSQL database with 26 tables
- Qdrant vector database
- Ollama local LLM integration (llama3.2:3b, phi3:mini)
- Nginx reverse proxy + Maicha web UI
- Docker Compose orchestration (8 services)
- Open WebUI chat interface
- Adminer database management"

echo ""
echo "=== Git repo initialized ==="
echo ""
echo "Next steps to connect to GitHub:"
echo ""
echo "1. Go to https://github.com/new"
echo "   - Repository name: maicha"
echo "   - Keep it Private"
echo "   - Do NOT initialize with README (we already have one)"
echo "   - Click 'Create repository'"
echo ""
echo "2. Then run these commands on your server:"
echo "   cd /opt/ai-server"
echo "   git remote add origin https://github.com/YOUR_USERNAME/maicha.git"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "3. On your local Linux machine:"
echo "   git clone https://github.com/YOUR_USERNAME/maicha.git"
echo "   cd maicha"
echo "   code .   # opens in VS Code"
echo ""
echo "4. After editing locally, push and deploy:"
echo "   # Local: git push"
echo "   # Server: cd /opt/ai-server && git pull && docker compose build fastapi && docker compose up -d"
echo ""
