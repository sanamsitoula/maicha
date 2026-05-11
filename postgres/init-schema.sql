-- ============================================
-- AI Automation Server - Complete Database Schema
-- ============================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- USER MANAGEMENT
-- ============================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    role VARCHAR(50) DEFAULT 'user',  -- 'admin', 'user', 'agent'
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    key_hash VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(100),  -- friendly name like "n8n-integration"
    permissions JSONB DEFAULT '["read"]',
    is_active BOOLEAN DEFAULT true,
    last_used_at TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- AGENT MEMORY & CONVERSATION HISTORY
-- ============================================

CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    agent_type VARCHAR(50) NOT NULL,  -- 'real-estate', 'restaurant', 'social-media', etc.
    title VARCHAR(255),
    status VARCHAR(20) DEFAULT 'active',  -- 'active', 'archived', 'closed'
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL,  -- 'user', 'assistant', 'system', 'tool'
    content TEXT NOT NULL,
    token_count INTEGER,
    model_used VARCHAR(100),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE agent_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_type VARCHAR(50) NOT NULL,
    task_description TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',  -- 'pending', 'running', 'completed', 'failed'
    priority INTEGER DEFAULT 5,  -- 1 = highest, 10 = lowest
    input_data JSONB DEFAULT '{}',
    output_data JSONB DEFAULT '{}',
    error_message TEXT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE agent_memory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_type VARCHAR(50) NOT NULL,
    memory_type VARCHAR(50) NOT NULL,  -- 'fact', 'preference', 'context', 'learned'
    content TEXT NOT NULL,
    importance FLOAT DEFAULT 0.5,  -- 0.0 to 1.0
    embedding_id VARCHAR(255),  -- reference to Qdrant vector
    metadata JSONB DEFAULT '{}',
    expires_at TIMESTAMP,  -- NULL means permanent
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- REAL ESTATE MODULE
-- ============================================

CREATE TABLE property_listings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    ai_description TEXT,  -- AI-generated enhanced description
    property_type VARCHAR(50),  -- 'house', 'apartment', 'condo', 'land', 'commercial'
    listing_type VARCHAR(20),  -- 'sale', 'rent'
    price DECIMAL(12, 2),
    currency VARCHAR(3) DEFAULT 'USD',
    bedrooms INTEGER,
    bathrooms DECIMAL(3, 1),
    area_sqft DECIMAL(10, 2),
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(100),
    zip_code VARCHAR(20),
    country VARCHAR(100) DEFAULT 'US',
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    features JSONB DEFAULT '[]',  -- ["pool", "garage", "garden"]
    images JSONB DEFAULT '[]',  -- list of image URLs
    status VARCHAR(20) DEFAULT 'active',  -- 'active', 'pending', 'sold', 'archived'
    listed_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE property_inquiries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id UUID REFERENCES property_listings(id) ON DELETE CASCADE,
    contact_name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    contact_phone VARCHAR(50),
    message TEXT,
    inquiry_type VARCHAR(50),  -- 'viewing', 'question', 'offer', 'general'
    ai_qualification TEXT,  -- AI's assessment of the lead
    lead_score INTEGER,  -- 1-100, AI-generated
    status VARCHAR(20) DEFAULT 'new',  -- 'new', 'contacted', 'qualified', 'closed'
    follow_up_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE client_contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(50),
    contact_type VARCHAR(20),  -- 'buyer', 'seller', 'renter', 'landlord'
    preferences JSONB DEFAULT '{}',  -- {"budget": 500000, "bedrooms": 3, "preferred_areas": ["downtown"]}
    notes TEXT,
    last_contact_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- RESTAURANT MODULE
-- ============================================

CREATE TABLE restaurants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    cuisine_type VARCHAR(100),
    address VARCHAR(500),
    phone VARCHAR(50),
    email VARCHAR(255),
    operating_hours JSONB DEFAULT '{}',  -- {"monday": {"open": "09:00", "close": "22:00"}}
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE menu_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100),  -- 'appetizer', 'main', 'dessert', 'drink', 'side'
    price DECIMAL(8, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    is_available BOOLEAN DEFAULT true,
    dietary_tags JSONB DEFAULT '[]',  -- ["vegetarian", "gluten-free", "vegan"]
    allergens JSONB DEFAULT '[]',  -- ["nuts", "dairy", "shellfish"]
    image_url VARCHAR(500),
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID REFERENCES restaurants(id),
    customer_name VARCHAR(255),
    customer_email VARCHAR(255),
    customer_phone VARCHAR(50),
    order_type VARCHAR(20) DEFAULT 'dine-in',  -- 'dine-in', 'takeout', 'delivery'
    status VARCHAR(20) DEFAULT 'pending',  -- 'pending', 'confirmed', 'preparing', 'ready', 'delivered', 'cancelled'
    subtotal DECIMAL(10, 2),
    tax DECIMAL(10, 2),
    total DECIMAL(10, 2),
    special_instructions TEXT,
    conversation_id UUID REFERENCES conversations(id),  -- links to chat that created this order
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    menu_item_id UUID REFERENCES menu_items(id),
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price DECIMAL(8, 2) NOT NULL,
    total_price DECIMAL(8, 2) NOT NULL,
    special_requests TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE reservations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID REFERENCES restaurants(id),
    customer_name VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255),
    customer_phone VARCHAR(50),
    party_size INTEGER NOT NULL,
    reservation_date DATE NOT NULL,
    reservation_time TIME NOT NULL,
    status VARCHAR(20) DEFAULT 'confirmed',  -- 'confirmed', 'cancelled', 'completed', 'no-show'
    special_requests TEXT,
    conversation_id UUID REFERENCES conversations(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- SOCIAL MEDIA MODULE
-- ============================================

CREATE TABLE social_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    platform VARCHAR(50) NOT NULL,  -- 'instagram', 'tiktok', 'facebook', 'twitter', 'linkedin', 'youtube'
    account_name VARCHAR(255),
    account_id VARCHAR(255),  -- platform-specific ID
    access_token_encrypted TEXT,  -- encrypted OAuth token
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',
    connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE content_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    social_account_id UUID REFERENCES social_accounts(id),
    content_type VARCHAR(50),  -- 'post', 'story', 'reel', 'tweet', 'article'
    platform VARCHAR(50) NOT NULL,
    caption TEXT,
    hashtags JSONB DEFAULT '[]',
    media_urls JSONB DEFAULT '[]',
    scheduled_for TIMESTAMP,
    status VARCHAR(20) DEFAULT 'draft',  -- 'draft', 'scheduled', 'publishing', 'published', 'failed'
    ai_generated BOOLEAN DEFAULT true,
    generation_prompt TEXT,  -- the prompt used to generate this content
    approval_status VARCHAR(20) DEFAULT 'pending',  -- 'pending', 'approved', 'rejected'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE published_posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_queue_id UUID REFERENCES content_queue(id),
    platform VARCHAR(50) NOT NULL,
    platform_post_id VARCHAR(255),  -- the ID the platform assigns after publishing
    post_url VARCHAR(500),
    published_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE post_analytics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    published_post_id UUID REFERENCES published_posts(id) ON DELETE CASCADE,
    impressions INTEGER DEFAULT 0,
    reach INTEGER DEFAULT 0,
    likes INTEGER DEFAULT 0,
    comments INTEGER DEFAULT 0,
    shares INTEGER DEFAULT 0,
    saves INTEGER DEFAULT 0,
    clicks INTEGER DEFAULT 0,
    engagement_rate DECIMAL(5, 4),  -- e.g., 0.0345 = 3.45%
    fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- MEDIA PIPELINE (Video/Audio Generation)
-- ============================================

CREATE TABLE media_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_type VARCHAR(50) NOT NULL,  -- 'video', 'image', 'audio', 'voiceover'
    status VARCHAR(20) DEFAULT 'queued',  -- 'queued', 'processing', 'completed', 'failed'
    priority INTEGER DEFAULT 5,
    input_data JSONB NOT NULL,  -- all parameters for this job
    output_data JSONB DEFAULT '{}',
    error_message TEXT,
    progress INTEGER DEFAULT 0,  -- 0-100
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE generated_scripts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    topic VARCHAR(255) NOT NULL,
    script_text TEXT NOT NULL,
    target_platform VARCHAR(50),  -- 'youtube', 'tiktok', 'instagram'
    target_duration_seconds INTEGER,
    model_used VARCHAR(100),
    generation_prompt TEXT,
    status VARCHAR(20) DEFAULT 'draft',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE generated_media (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    media_job_id UUID REFERENCES media_jobs(id),
    media_type VARCHAR(20) NOT NULL,  -- 'image', 'audio', 'video'
    file_path VARCHAR(500) NOT NULL,
    file_size_bytes BIGINT,
    duration_seconds DECIMAL(8, 2),
    format VARCHAR(20),  -- 'mp4', 'mp3', 'png', 'wav'
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE render_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    script_id UUID REFERENCES generated_scripts(id),
    voiceover_media_id UUID REFERENCES generated_media(id),
    status VARCHAR(20) DEFAULT 'pending',  -- 'pending', 'rendering', 'completed', 'failed'
    image_ids JSONB DEFAULT '[]',  -- list of generated_media IDs for images
    output_media_id UUID REFERENCES generated_media(id),
    render_settings JSONB DEFAULT '{}',  -- resolution, fps, etc.
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- ANALYTICS & TRACKING
-- ============================================

CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(100) NOT NULL,  -- 'agent_call', 'api_request', 'order_placed', 'lead_created'
    source VARCHAR(50),  -- 'real-estate-agent', 'restaurant-agent', 'api', 'n8n'
    user_id UUID REFERENCES users(id),
    data JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE conversion_tracking (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    funnel_name VARCHAR(100) NOT NULL,  -- 'real-estate-lead', 'restaurant-order', 'social-signup'
    step_name VARCHAR(100) NOT NULL,  -- 'viewed', 'clicked', 'inquired', 'converted'
    user_id UUID REFERENCES users(id),
    session_id VARCHAR(255),
    data JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- TASK QUEUE (Background Jobs)
-- ============================================

CREATE TABLE scheduled_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_name VARCHAR(255) NOT NULL,
    task_type VARCHAR(50) NOT NULL,  -- 'cron', 'one-time', 'recurring'
    cron_expression VARCHAR(100),  -- e.g., '0 9 * * *' = every day at 9am
    handler VARCHAR(255) NOT NULL,  -- which function/endpoint to call
    payload JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    last_run_at TIMESTAMP,
    next_run_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE job_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID REFERENCES scheduled_tasks(id),
    agent_task_id UUID REFERENCES agent_tasks(id),
    status VARCHAR(20) NOT NULL,  -- 'started', 'completed', 'failed'
    message TEXT,
    duration_ms INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Speed up common queries
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at);
CREATE INDEX idx_conversations_agent ON conversations(agent_type, status);
CREATE INDEX idx_agent_tasks_status ON agent_tasks(status, agent_type);
CREATE INDEX idx_agent_memory_type ON agent_memory(agent_type, memory_type);
CREATE INDEX idx_property_listings_status ON property_listings(status, listing_type);
CREATE INDEX idx_property_listings_location ON property_listings(city, state, zip_code);
CREATE INDEX idx_orders_status ON orders(status, restaurant_id);
CREATE INDEX idx_content_queue_status ON content_queue(status, scheduled_for);
CREATE INDEX idx_media_jobs_status ON media_jobs(status, job_type);
CREATE INDEX idx_events_type ON events(event_type, created_at);
CREATE INDEX idx_events_source ON events(source, created_at);

-- ============================================
-- DONE! Schema complete.
-- ============================================
