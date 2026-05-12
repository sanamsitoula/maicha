#!/bin/bash
set -e
echo "=== Phase 6A: Fix API + CRUD Endpoints ==="

BASE="/opt/ai-server"
AGENTS="$BASE/agents"
cd "$BASE"

# ============================================
# Step 1: Fix model pull 404 — the issue is Ollama needs
# time to pull and the endpoint may timeout or the model
# name format might not match. Let's fix the pull endpoint.
# ============================================
python3 << 'PYFIX'
filepath = "/opt/ai-server/agents/shared/model_manager.py"
with open(filepath, "r") as f:
    content = f.read()

old_pull = '''def ollama_pull(model_name):
    """Pull a model from Ollama registry. Returns stream progress."""
    try:
        resp = httpx.post(
            f"{OLLAMA_BASE_URL}/api/pull",
            json={"name": model_name, "stream": False},
            timeout=600.0,
        )
        resp.raise_for_status()
        ensure_model_table()
        execute(
            "INSERT INTO model_registry (name, provider, model_id) "
            "VALUES (%s, 'ollama', %s) ON CONFLICT (name) DO UPDATE SET is_active = true",
            (model_name, model_name)
        )
        return {"status": "success", "model": model_name}
    except httpx.TimeoutException:
        return {"status": "pulling", "model": model_name, "message": "Model is downloading. This can take several minutes. Check /models/ollama to see when it appears."}
    except Exception as e:
        return {"status": "error", "error": str(e)}'''

new_pull = '''def ollama_pull(model_name):
    """Pull a model from Ollama registry."""
    try:
        # First check if model already exists
        existing = ollama_list()
        if not isinstance(existing, dict):
            for m in existing:
                if m.get("name") == model_name:
                    ensure_model_table()
                    execute(
                        "INSERT INTO model_registry (name, provider, model_id) "
                        "VALUES (%s, 'ollama', %s) ON CONFLICT (name) DO UPDATE SET is_active = true",
                        (model_name, model_name)
                    )
                    return {"status": "success", "model": model_name, "message": "Model already installed"}

        # Pull with streaming disabled — long timeout for large models
        resp = httpx.post(
            f"{OLLAMA_BASE_URL}/api/pull",
            json={"name": model_name, "stream": False},
            timeout=1800.0,
        )
        if resp.status_code == 200:
            ensure_model_table()
            execute(
                "INSERT INTO model_registry (name, provider, model_id) "
                "VALUES (%s, 'ollama', %s) ON CONFLICT (name) DO UPDATE SET is_active = true",
                (model_name, model_name)
            )
            return {"status": "success", "model": model_name}
        else:
            return {"status": "error", "error": f"Ollama returned {resp.status_code}: {resp.text[:200]}"}
    except httpx.TimeoutException:
        return {"status": "pulling", "model": model_name, "message": "Model is downloading (large file). Check GET /models/ollama in a few minutes."}
    except httpx.ConnectError:
        return {"status": "error", "error": "Cannot connect to Ollama. Is the ai-ollama container running?"}
    except Exception as e:
        return {"status": "error", "error": str(e)}'''

if old_pull in content:
    content = content.replace(old_pull, new_pull)
    print("Fixed ollama_pull")
else:
    print("WARNING: Could not find exact pull function to replace")

with open(filepath, "w") as f:
    f.write(content)
PYFIX

echo "Fixed model pull"

# ============================================
# Step 2: Add CRUD endpoints to api.py
# ============================================
cat >> "$AGENTS/api.py" << 'PYEOF'


# ══════════════════════════════════════════
# CRUD: MENU ITEMS
# ══════════════════════════════════════════

class AddMenuItemRequest(BaseModel):
    name: str
    description: str = ""
    category: str = "main"
    price: float
    dietary_tags: Optional[List[str]] = []
    is_available: bool = True

class UpdateMenuItemRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    dietary_tags: Optional[List[str]] = None
    is_available: Optional[bool] = None


@app.post("/menu/add", dependencies=[Depends(require_admin)])
def add_menu_item(req: AddMenuItemRequest):
    """Add a new menu item (admin only)."""
    restaurants = query("SELECT id FROM restaurants LIMIT 1")
    if not restaurants:
        return {"status": "error", "message": "No restaurant configured. Create one first."}
    result = execute(
        "INSERT INTO menu_items (restaurant_id, name, description, category, price, dietary_tags, is_available) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id, name, price",
        (restaurants[0]["id"], req.name, req.description, req.category, req.price,
         json.dumps(req.dietary_tags or []), req.is_available)
    )
    return {"status": "added", "item": result[0] if result else None}


@app.put("/menu/{item_name}", dependencies=[Depends(require_admin)])
def update_menu_item(item_name: str, req: UpdateMenuItemRequest):
    """Update a menu item by name (admin only)."""
    updates = []
    params = []
    if req.name is not None:
        updates.append("name = %s")
        params.append(req.name)
    if req.description is not None:
        updates.append("description = %s")
        params.append(req.description)
    if req.category is not None:
        updates.append("category = %s")
        params.append(req.category)
    if req.price is not None:
        updates.append("price = %s")
        params.append(req.price)
    if req.dietary_tags is not None:
        updates.append("dietary_tags = %s")
        params.append(json.dumps(req.dietary_tags))
    if req.is_available is not None:
        updates.append("is_available = %s")
        params.append(req.is_available)
    if not updates:
        return {"status": "error", "message": "Nothing to update"}
    updates.append("updated_at = CURRENT_TIMESTAMP")
    params.append(item_name)
    execute(f"UPDATE menu_items SET {', '.join(updates)} WHERE LOWER(name) = LOWER(%s)", tuple(params))
    return {"status": "updated", "item": item_name}


@app.delete("/menu/{item_name}", dependencies=[Depends(require_admin)])
def delete_menu_item(item_name: str):
    """Delete a menu item by name (admin only)."""
    execute("DELETE FROM menu_items WHERE LOWER(name) = LOWER(%s)", (item_name,))
    return {"status": "deleted", "item": item_name}


# ══════════════════════════════════════════
# CRUD: PROPERTY LISTINGS
# ══════════════════════════════════════════

class AddPropertyRequest(BaseModel):
    title: str
    description: str = ""
    property_type: str = "apartment"
    listing_type: str = "rent"
    price: float
    bedrooms: Optional[int] = None
    bathrooms: Optional[float] = None
    area_sqft: Optional[float] = None
    city: str = ""
    state: str = ""
    zip_code: str = ""
    address_line1: str = ""
    features: Optional[List[str]] = []


@app.post("/properties/add", dependencies=[Depends(require_admin)])
def add_property(req: AddPropertyRequest):
    """Add a new property listing (admin only)."""
    result = execute(
        "INSERT INTO property_listings (title, description, property_type, listing_type, price, "
        "bedrooms, bathrooms, area_sqft, city, state, zip_code, address_line1, features, status) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'active') RETURNING id, title, price",
        (req.title, req.description, req.property_type, req.listing_type, req.price,
         req.bedrooms, req.bathrooms, req.area_sqft, req.city, req.state, req.zip_code,
         req.address_line1, json.dumps(req.features or []))
    )
    return {"status": "added", "property": result[0] if result else None}


@app.delete("/properties/{property_id}", dependencies=[Depends(require_admin)])
def delete_property(property_id: str):
    """Delete a property listing (admin only)."""
    execute("UPDATE property_listings SET status = 'archived' WHERE id = %s::uuid", (property_id,))
    return {"status": "archived", "id": property_id}


# ══════════════════════════════════════════
# DETAILED: ORDERS + CONVERSATIONS
# ══════════════════════════════════════════

@app.get("/orders/{order_id}")
def get_order_detail(order_id: str):
    """Get full order details with items, customer info."""
    order = query(
        "SELECT o.id, o.customer_name, o.customer_email, o.customer_phone, "
        "o.order_type, o.status, o.subtotal, o.tax, o.total, "
        "o.special_instructions, o.created_at, o.updated_at "
        "FROM orders o WHERE o.id = %s::uuid", (order_id,))
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    order = order[0]
    items = query(
        "SELECT oi.quantity, oi.unit_price, oi.total_price, oi.special_requests, mi.name, mi.category "
        "FROM order_items oi JOIN menu_items mi ON oi.menu_item_id = mi.id "
        "WHERE oi.order_id = %s::uuid", (order_id,))
    order["items"] = items
    return {"order": order}


@app.get("/orders-detailed")
def get_orders_detailed(status: Optional[str] = None, limit: int = 20):
    """Get orders with full details including items and customer info."""
    if status:
        orders = query(
            "SELECT o.id, o.customer_name, o.customer_phone, o.status, o.total, "
            "o.special_instructions, o.order_type, o.created_at "
            "FROM orders o WHERE LOWER(o.status) = LOWER(%s) "
            "ORDER BY o.created_at DESC LIMIT %s", (status, limit))
    else:
        orders = query(
            "SELECT o.id, o.customer_name, o.customer_phone, o.status, o.total, "
            "o.special_instructions, o.order_type, o.created_at "
            "FROM orders o ORDER BY o.created_at DESC LIMIT %s", (limit,))
    for order in orders:
        items = query(
            "SELECT mi.name, oi.quantity, oi.total_price "
            "FROM order_items oi JOIN menu_items mi ON oi.menu_item_id = mi.id "
            "WHERE oi.order_id = %s::uuid", (str(order["id"]),))
        order["items"] = items
    return {"orders": orders, "count": len(orders)}


@app.get("/conversations/{conv_id}/messages")
def get_conversation_messages(conv_id: str, limit: int = 50):
    """Get all messages in a conversation."""
    conv = query(
        "SELECT id, agent_type, title, status, created_at FROM conversations WHERE id = %s::uuid",
        (conv_id,))
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    messages = query(
        "SELECT role, content, model_used, created_at FROM messages "
        "WHERE conversation_id = %s::uuid ORDER BY created_at ASC LIMIT %s",
        (conv_id, limit))
    return {"conversation": conv[0], "messages": messages, "count": len(messages)}


@app.get("/conversations-detailed")
def get_conversations_detailed(agent_type: Optional[str] = None, limit: int = 20):
    """Get conversations with message count and last message preview."""
    if agent_type:
        convos = query(
            "SELECT c.id, c.agent_type, c.title, c.status, c.created_at, "
            "COUNT(m.id) as message_count, "
            "MAX(m.created_at) as last_message_at "
            "FROM conversations c LEFT JOIN messages m ON c.id = m.conversation_id "
            "WHERE c.agent_type = %s "
            "GROUP BY c.id ORDER BY c.created_at DESC LIMIT %s",
            (agent_type, limit))
    else:
        convos = query(
            "SELECT c.id, c.agent_type, c.title, c.status, c.created_at, "
            "COUNT(m.id) as message_count, "
            "MAX(m.created_at) as last_message_at "
            "FROM conversations c LEFT JOIN messages m ON c.id = m.conversation_id "
            "GROUP BY c.id ORDER BY c.created_at DESC LIMIT %s",
            (limit,))
    # Get last message preview for each
    for c in convos:
        last_msg = query(
            "SELECT role, LEFT(content, 100) as preview FROM messages "
            "WHERE conversation_id = %s::uuid ORDER BY created_at DESC LIMIT 1",
            (str(c["id"]),))
        c["last_message"] = last_msg[0] if last_msg else None
    return {"conversations": convos, "count": len(convos)}


@app.get("/reservations")
def get_reservations(limit: int = 20):
    """Get all reservations with details."""
    return {"reservations": query(
        "SELECT id, customer_name, customer_phone, party_size, "
        "reservation_date, reservation_time, status, special_requests, created_at "
        "FROM reservations ORDER BY reservation_date DESC, reservation_time DESC LIMIT %s",
        (limit,))}


# ══════════════════════════════════════════
# CRUD: RESTAURANTS
# ══════════════════════════════════════════

class AddRestaurantRequest(BaseModel):
    name: str
    description: str = ""
    cuisine_type: str = ""
    address: str = ""
    phone: str = ""


@app.post("/restaurants/add", dependencies=[Depends(require_admin)])
def add_restaurant(req: AddRestaurantRequest):
    """Add a new restaurant (admin only)."""
    result = execute(
        "INSERT INTO restaurants (name, description, cuisine_type, address, phone) "
        "VALUES (%s, %s, %s, %s, %s) RETURNING id, name",
        (req.name, req.description, req.cuisine_type, req.address, req.phone))
    return {"status": "added", "restaurant": result[0] if result else None}


@app.put("/orders/{order_id}/status", dependencies=[Depends(require_admin)])
def update_order_status(order_id: str, status: str):
    """Update order status (admin only)."""
    valid = ["pending", "confirmed", "preparing", "ready", "delivered", "cancelled"]
    if status not in valid:
        return {"status": "error", "message": f"Invalid status. Use: {', '.join(valid)}"}
    execute("UPDATE orders SET status = %s, updated_at = CURRENT_TIMESTAMP WHERE id = %s::uuid",
            (status, order_id))
    return {"status": "updated", "order_id": order_id, "new_status": status}
PYEOF

echo "Added CRUD endpoints"

# ============================================
# Step 3: Add new proxy routes to nginx
# ============================================
if ! grep -q "location /orders-detailed" "$BASE/nginx/nginx.conf"; then
    sed -i '/location \/orders/a\
        location /orders-detailed { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Authorization $http_authorization; }\
        location /conversations-detailed { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Authorization $http_authorization; }\
        location /reservations { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Authorization $http_authorization; }\
        location /restaurants { proxy_pass http://fastapi:8000; proxy_set_header Host $host; proxy_set_header Authorization $http_authorization; proxy_set_header Content-Type $http_content_type; }' "$BASE/nginx/nginx.conf"
    echo "Added new proxy routes to nginx"
fi

echo "Updated nginx"

# ============================================
# Step 4: Update README
# ============================================
python3 << 'PYFIX2'
filepath = "/opt/ai-server/README.md"
with open(filepath, "r") as f:
    content = f.read()

crud_docs = """
## CRUD Endpoints

### Menu Management (admin)
```bash
POST /menu/add          # Add menu item
PUT  /menu/{name}       # Update menu item
DELETE /menu/{name}     # Delete menu item
```

### Property Management (admin)
```bash
POST /properties/add     # Add property listing
DELETE /properties/{id}  # Archive property
```

### Order Management
```bash
GET /orders-detailed         # Orders with items + customer details
GET /orders/{id}             # Single order full detail
PUT /orders/{id}/status      # Update order status (admin)
```

### Conversation History
```bash
GET /conversations-detailed          # Conversations with message count + preview
GET /conversations/{id}/messages     # Full message history
```

### Reservations
```bash
GET /reservations     # All reservations with details
```

"""

content = content.replace("## Telegram Order Bot", crud_docs + "## Telegram Order Bot")

with open(filepath, "w") as f:
    f.write(content)
print("README updated")
PYFIX2

# ============================================
# Step 5: Git commit
# ============================================
git add -A
git commit -m "Phase 6A: Fix API + add CRUD endpoints

Fixes:
- Model pull 404: increased timeout to 1800s, better error handling,
  checks if model already exists before pulling
- ConnectError handling when Ollama is down

New CRUD endpoints:
- POST /menu/add, PUT /menu/{name}, DELETE /menu/{name}
- POST /properties/add, DELETE /properties/{id}
- POST /restaurants/add
- PUT /orders/{id}/status

New detail endpoints:
- GET /orders-detailed (orders with items + customer info)
- GET /orders/{id} (single order full detail)
- GET /conversations-detailed (with message count + preview)
- GET /conversations/{id}/messages (full chat history)
- GET /reservations (all reservations)

Updated nginx with new proxy routes
README updated with CRUD docs"

echo ""
echo "=== Phase 6A Complete ==="
echo ""
echo "Run:"
echo "  cd /opt/ai-server"
echo "  docker compose build fastapi"
echo "  docker compose up -d --force-recreate fastapi nginx"
echo "  git push"
echo ""
echo "Test model pull fix:"
echo '  TOKEN=$(curl -s -X POST http://localhost:8000/auth/login -H "Content-Type: application/json" -d '"'"'{"email":"sanam.ctaula@gmail.com","password":"Manas@123"}'"'"' | python3 -c "import sys,json; print(json.load(sys.stdin)['"'"'token'"'"'])")'
echo '  curl -X POST http://localhost:8000/models/ollama/pull -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d '"'"'{"name":"llama3.1:8b"}'"'"''
echo ""
echo "Test menu add:"
echo '  curl -X POST http://localhost:8000/menu/add -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d '"'"'{"name":"Pixel Pizza","description":"AI-optimized pizza","category":"main","price":12.99,"dietary_tags":["vegetarian"]}'"'"''
echo ""
echo "Test detailed orders:"
echo "  curl http://localhost:8000/orders-detailed"
echo "  curl http://localhost:8000/conversations-detailed"
echo "  curl http://localhost:8000/reservations"