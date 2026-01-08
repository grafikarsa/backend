#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting database migration for Comments feature...${NC}"

# Navigate to the backend directory to find .env
# Assuming script is run from backend/scripts/ or backend/
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"

ENV_FILE="$BACKEND_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    echo "Loading configuration from $ENV_FILE"
    # Export variables from .env
    set -a
    source "$ENV_FILE"
    set +a
else
    echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
    exit 1
fi

# Check required variables
if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ] || [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
    echo -e "${RED}Error: Database configuration missing in .env${NC}"
    echo "Required: DB_HOST, DB_PORT, DB_USER, DB_NAME, DB_PASSWORD"
    exit 1
fi

export PGPASSWORD=$DB_PASSWORD

# SQL Queries
SQL_COMMANDS="
-- 1. Update ENUM type (Handle 'already exists' gracefully with DO block for strict postgres encironments if needed, 
-- but IF NOT EXISTS is supported in newer pg for ALTER TYPE ADD VALUE. 
-- For older PG (<12), we might need catch exception, but let's try standard approach first or just run it.)
-- Note: 'ALTER TYPE ... ADD VALUE IF NOT EXISTS' is available in PostgreSQL 12+.
-- If server is older, we might see error if value exists, which is acceptable to ignore or handle specificially.

DO \$\$
BEGIN
    ALTER TYPE notification_type ADD VALUE 'new_comment';
EXCEPTION
    WHEN duplicate_object THEN null;
END \$\$;

DO \$\$
BEGIN
    ALTER TYPE notification_type ADD VALUE 'reply_comment';
EXCEPTION
    WHEN duplicate_object THEN null;
END \$\$;

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

-- 4. Create Trigger
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_comments_updated_at') THEN
        CREATE TRIGGER trg_comments_updated_at 
            BEFORE UPDATE ON comments 
            FOR EACH ROW 
            EXECUTE FUNCTION update_updated_at();
    END IF;
END \$\$;
"

echo "Connecting to database $DB_NAME..."

# Check if psql is installed
if command -v psql &> /dev/null; then
    echo "Using system psql..."
    # If DB_HOST is 'postgres' (docker service name), map to localhost if running on host
    HOST=$DB_HOST
    # Simple check if DB_HOST matches common docker service names
    if [ "$HOST" = "postgres" ] || [ "$HOST" = "db" ]; then
        HOST="localhost"
    fi
    
    echo "$SQL_COMMANDS" | PGPASSWORD=$DB_PASSWORD psql -h "$HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1
    EXIT_CODE=$?
elif command -v docker &> /dev/null; then
    CONTAINER_NAME="backend-postgres-1"
    echo "psql not found on host. Attempting to use Docker container: $CONTAINER_NAME"
    
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Executing SQL inside container..."
        echo "$SQL_COMMANDS" | docker exec -i -e PGPASSWORD=$DB_PASSWORD $CONTAINER_NAME psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1
        EXIT_CODE=$?
    else
        echo -e "${RED}Error: psql not found and Docker container '$CONTAINER_NAME' is not running.${NC}"
        echo "Available containers:"
        docker ps --format '{{.Names}}'
        exit 1
    fi
else
    echo -e "${RED}Error: Neither psql nor docker command found.${NC}"
    exit 1
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ Migration completed successfully!${NC}"
else
    echo -e "${RED}❌ Migration failed.${NC}"
    exit 1
fi
