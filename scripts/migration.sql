-- Migration for Comments Feature
-- Run with: cat backend/scripts/migration.sql | docker exec -i backend-postgres-1 psql -U grafikarsa -d grafikarsa

-- 1. Update ENUM type (Safe for re-run)
DO $$
BEGIN
    ALTER TYPE notification_type ADD VALUE 'new_comment';
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$
BEGIN
    ALTER TYPE notification_type ADD VALUE 'reply_comment';
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Create Comments Table
CREATE TABLE IF NOT EXISTS comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portfolio_id UUID NOT NULL REFERENCES portfolios(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    is_edited BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 3. Create Indexes
CREATE INDEX IF NOT EXISTS idx_comments_portfolio_id ON comments(portfolio_id);
CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent_id ON comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_comments_created_at ON comments(created_at);

-- 4. Create Trigger for updated_at
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_comments_updated_at') THEN
        CREATE TRIGGER trg_comments_updated_at 
            BEFORE UPDATE ON comments 
            FOR EACH ROW 
            EXECUTE FUNCTION update_updated_at();
    END IF;
END $$;
