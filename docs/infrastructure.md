# Grafikarsa Backend Infrastructure

## Overview

Dokumentasi infrastruktur untuk backend Grafikarsa yang berjalan dalam Docker containers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         PRODUCTION SERVER                        │
│                        (VPS / Cloud VM)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│    ┌──────────────────────────────────────────────────────┐     │
│    │                      NGINX                            │     │
│    │              (Reverse Proxy + SSL)                    │     │
│    │                    :80 / :443                         │     │
│    └──────────────────────────────────────────────────────┘     │
│           │                    │                    │            │
│           ▼                    ▼                    ▼            │
│    ┌────────────┐      ┌────────────┐      ┌────────────┐       │
│    │  Backend   │      │   MinIO    │      │   MinIO    │       │
│    │  (Golang)  │      │    API     │      │  Console   │       │
│    │   :8080    │      │   :9000    │      │   :9001    │       │
│    └────────────┘      └────────────┘      └────────────┘       │
│           │                    │                                 │
│           ▼                    ▼                                 │
│    ┌────────────┐      ┌────────────┐                           │
│    │ PostgreSQL │      │   MinIO    │                           │
│    │   :5432    │      │   Data     │                           │
│    └────────────┘      └────────────┘                           │
│                                                                  │
│    Docker Network: grafikarsa-network                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Component | Technology | Version | Port |
|-----------|------------|---------|------|
| API Server | Golang + GoFiber | 1.23+ | 8080 |
| Database | PostgreSQL | 16 | 5432 |
| Object Storage | MinIO | latest | 9000, 9001 |
| Reverse Proxy | Nginx | latest | 80, 443 |
| Container | Docker + Compose | 24+ | - |

## Directory Structure

```
backend/
├── docker-compose.yml          # Main compose file
├── docker-compose.dev.yml      # Development overrides
├── docker-compose.prod.yml     # Production overrides
├── Dockerfile                  # Backend image
├── .env.example                # Environment template
├── .env                        # Local environment (gitignored)
│
├── nginx/
│   ├── nginx.conf              # Nginx configuration
│   └── ssl/                    # SSL certificates
│
├── scripts/
│   ├── init-db.sh              # Database initialization
│   ├── init-minio.sh           # MinIO bucket setup
│   └── backup.sh               # Backup script
│
├── cmd/
│   └── api/
│       └── main.go
│
├── internal/
│   └── ...
│
└── docs/
    ├── api.md
    └── infrastructure.md
```

---

## Docker Compose Configuration

### docker-compose.yml (Base)

```yaml
version: '3.8'

services:
  # ===================
  # Golang Backend API
  # ===================
  backend:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: grafikarsa-backend
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - APP_ENV=${APP_ENV:-development}
      - APP_PORT=8080
      - DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}?sslmode=disable
      - MINIO_ENDPOINT=minio:9000
      - MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}
      - MINIO_SECRET_KEY=${MINIO_SECRET_KEY}
      - MINIO_BUCKET=${MINIO_BUCKET}
      - MINIO_USE_SSL=false
      - JWT_ACCESS_SECRET=${JWT_ACCESS_SECRET}
      - JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
      - STORAGE_PUBLIC_URL=${STORAGE_PUBLIC_URL}
    depends_on:
      postgres:
        condition: service_healthy
      minio:
        condition: service_healthy
    networks:
      - grafikarsa-network
    volumes:
      - ./logs:/app/logs

  # ===================
  # PostgreSQL Database
  # ===================
  postgres:
    image: postgres:16-alpine
    container_name: grafikarsa-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=${DB_NAME}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./scripts/init-db.sh:/docker-entrypoint-initdb.d/init-db.sh:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - grafikarsa-network

  # ===================
  # MinIO Object Storage
  # ===================
  minio:
    image: minio/minio:latest
    container_name: grafikarsa-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=${MINIO_ACCESS_KEY}
      - MINIO_ROOT_PASSWORD=${MINIO_SECRET_KEY}
    volumes:
      - minio_data:/data
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - grafikarsa-network

  # ===================
  # MinIO Setup (one-time)
  # ===================
  minio-setup:
    image: minio/mc:latest
    container_name: grafikarsa-minio-setup
    depends_on:
      minio:
        condition: service_healthy
    entrypoint: >
      /bin/sh -c "
      mc alias set myminio http://minio:9000 ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY};
      mc mb myminio/${MINIO_BUCKET} --ignore-existing;
      mc anonymous set download myminio/${MINIO_BUCKET}/avatars;
      mc anonymous set download myminio/${MINIO_BUCKET}/banners;
      mc anonymous set download myminio/${MINIO_BUCKET}/thumbnails;
      mc anonymous set download myminio/${MINIO_BUCKET}/portfolio-images;
      echo 'MinIO setup completed';
      exit 0;
      "
    networks:
      - grafikarsa-network

networks:
  grafikarsa-network:
    driver: bridge

volumes:
  postgres_data:
  minio_data:
```


### docker-compose.dev.yml (Development)

```yaml
version: '3.8'

services:
  backend:
    build:
      target: development
    volumes:
      - .:/app
      - /app/tmp
    environment:
      - APP_ENV=development
      - GIN_MODE=debug

  postgres:
    ports:
      - "5432:5432"  # Expose untuk local tools (DBeaver, etc)

  minio:
    ports:
      - "9000:9000"  # MinIO API
      - "9001:9001"  # MinIO Console
```

### docker-compose.prod.yml (Production)

```yaml
version: '3.8'

services:
  backend:
    build:
      target: production
    environment:
      - APP_ENV=production
      - GIN_MODE=release
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M

  postgres:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G

  minio:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  # ===================
  # Nginx Reverse Proxy
  # ===================
  nginx:
    image: nginx:alpine
    container_name: grafikarsa-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - backend
      - minio
    networks:
      - grafikarsa-network
```

---

## Dockerfile

```dockerfile
# ================================
# Build Stage
# ================================
FROM golang:1.23-alpine AS builder

WORKDIR /build

# Install dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /build/server ./cmd/api

# ================================
# Development Stage
# ================================
FROM golang:1.23-alpine AS development

WORKDIR /app

# Install air for hot reload
RUN go install github.com/air-verse/air@latest

COPY go.mod go.sum ./
RUN go mod download

COPY . .

CMD ["air", "-c", ".air.toml"]

# ================================
# Production Stage
# ================================
FROM alpine:3.19 AS production

WORKDIR /app

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates tzdata

# Copy binary from builder
COPY --from=builder /build/server .

# Create non-root user
RUN adduser -D -g '' appuser
USER appuser

EXPOSE 8080

CMD ["./server"]
```

---

## Environment Variables

### .env.example

```bash
# ===================
# Application
# ===================
APP_ENV=development
APP_PORT=8080
APP_URL=http://localhost:8080

# ===================
# Database (PostgreSQL)
# ===================
DB_HOST=postgres
DB_PORT=5432
DB_USER=grafikarsa
DB_PASSWORD=your_secure_password_here
DB_NAME=grafikarsa

# Connection string (auto-constructed in app)
# DATABASE_URL=postgres://grafikarsa:password@postgres:5432/grafikarsa?sslmode=disable

# ===================
# MinIO (Object Storage)
# ===================
MINIO_ENDPOINT=minio:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=your_minio_secret_here
MINIO_BUCKET=grafikarsa
MINIO_USE_SSL=false

# Public URL for accessing files (adjust for production)
STORAGE_PUBLIC_URL=http://localhost:9000/grafikarsa

# ===================
# JWT Authentication
# ===================
JWT_ACCESS_SECRET=your_32_char_access_secret_here_
JWT_REFRESH_SECRET=your_32_char_refresh_secret_here
JWT_ACCESS_EXPIRY=15m
JWT_REFRESH_EXPIRY=168h

# ===================
# Admin Configuration
# ===================
ADMIN_LOGIN_PATH=loginadmin

# ===================
# CORS (comma-separated origins)
# ===================
CORS_ORIGINS=http://localhost:3000,http://localhost:5173

# ===================
# Rate Limiting
# ===================
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_DURATION=1m
```

### Production .env Notes

```bash
# Production adjustments:
APP_ENV=production
APP_URL=https://api.grafikarsa.com

# Use strong passwords!
DB_PASSWORD=<generate: openssl rand -base64 32>
MINIO_SECRET_KEY=<generate: openssl rand -base64 32>
JWT_ACCESS_SECRET=<generate: openssl rand -base64 32>
JWT_REFRESH_SECRET=<generate: openssl rand -base64 32>

# Production storage URL
STORAGE_PUBLIC_URL=https://grafikarsa.com/storage

# Production CORS
CORS_ORIGINS=https://grafikarsa.com,https://www.grafikarsa.com
```

---

## Nginx Configuration

### nginx/nginx.conf

```nginx
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log warn;

    # Performance
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout 65;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    # File upload size
    client_max_body_size 20M;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/s;

    # Upstream servers
    upstream backend {
        server backend:8080;
    }

    upstream minio {
        server minio:9000;
    }

    # HTTP -> HTTPS redirect
    server {
        listen 80;
        server_name grafikarsa.com www.grafikarsa.com;
        return 301 https://$server_name$request_uri;
    }

    # Main HTTPS server
    server {
        listen 443 ssl http2;
        server_name grafikarsa.com www.grafikarsa.com;

        # SSL Configuration
        ssl_certificate     /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
        ssl_prefer_server_ciphers off;

        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # API endpoints
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://backend/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Auth endpoints (stricter rate limit)
        location /api/v1/auth/ {
            limit_req zone=auth burst=5 nodelay;
            
            proxy_pass http://backend/api/v1/auth/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Static files from MinIO
        location /storage/ {
            proxy_pass http://minio/grafikarsa/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            
            # Cache static files
            proxy_cache_valid 200 1d;
            add_header Cache-Control "public, max-age=86400";
        }

        # MinIO Console (optional, for admin)
        location /minio-console/ {
            proxy_pass http://minio:9001/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }

        # Health check
        location /health {
            proxy_pass http://backend/health;
        }
    }
}
```

---

## Scripts

### scripts/init-db.sh

```bash
#!/bin/bash
set -e

# This script runs automatically when PostgreSQL container starts for the first time

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Enable required extensions
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    
    -- Log
    \echo 'Extensions created successfully'
EOSQL

echo "Database initialization completed"
```

### scripts/backup.sh

```bash
#!/bin/bash

# Configuration
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

# Create backup directory
mkdir -p $BACKUP_DIR

# PostgreSQL backup
echo "Backing up PostgreSQL..."
docker exec grafikarsa-postgres pg_dump -U $DB_USER $DB_NAME | gzip > $BACKUP_DIR/postgres_$DATE.sql.gz

# MinIO backup (sync to backup location)
echo "Backing up MinIO data..."
docker run --rm \
    -v grafikarsa-backend_minio_data:/data:ro \
    -v $BACKUP_DIR:/backup \
    alpine tar czf /backup/minio_$DATE.tar.gz -C /data .

# Cleanup old backups
echo "Cleaning up old backups..."
find $BACKUP_DIR -name "*.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $DATE"
```

---

## Deployment Commands

### Development

```bash
# Start all services
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# View logs
docker compose logs -f backend

# Rebuild after code changes
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build backend

# Stop all
docker compose down
```

### Production

```bash
# First time setup
cp .env.example .env
# Edit .env with production values

# Start all services
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# View logs
docker compose logs -f

# Update/redeploy
git pull
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

# Stop all
docker compose down

# Stop and remove volumes (DANGER: deletes data!)
docker compose down -v
```

### Database Operations

```bash
# Access PostgreSQL CLI
docker exec -it grafikarsa-postgres psql -U grafikarsa -d grafikarsa

# Run migrations (via backend)
docker exec grafikarsa-backend ./server migrate

# Backup database
docker exec grafikarsa-postgres pg_dump -U grafikarsa grafikarsa > backup.sql

# Restore database
cat backup.sql | docker exec -i grafikarsa-postgres psql -U grafikarsa -d grafikarsa
```

### MinIO Operations

```bash
# Access MinIO Console
# Development: http://localhost:9001
# Production: https://grafikarsa.com/minio-console/

# Using MinIO Client (mc)
docker exec -it grafikarsa-minio mc alias set local http://localhost:9000 minioadmin minioadmin

# List buckets
docker exec grafikarsa-minio mc ls local

# List files in bucket
docker exec grafikarsa-minio mc ls local/grafikarsa/avatars/
```

---

## Server Requirements

### Minimum (Development/Small)

| Resource | Spec |
|----------|------|
| CPU | 1 vCPU |
| RAM | 2 GB |
| Storage | 20 GB SSD |
| OS | Ubuntu 22.04 / Debian 12 |

### Recommended (Production)

| Resource | Spec |
|----------|------|
| CPU | 2 vCPU |
| RAM | 4 GB |
| Storage | 50 GB SSD |
| OS | Ubuntu 22.04 LTS |

### VPS Providers

| Provider | Plan | Price/month |
|----------|------|-------------|
| DigitalOcean | Basic Droplet 2GB | $12 |
| Vultr | Cloud Compute 2GB | $12 |
| Linode | Shared 2GB | $12 |
| Hetzner | CX21 | €4.85 (~$5) |
| IDCloudHost | VM 2GB | Rp 100k (~$6) |

---

## SSL Certificate Setup

### Using Certbot (Let's Encrypt)

```bash
# Install certbot
apt install certbot

# Generate certificate (stop nginx first)
docker compose stop nginx
certbot certonly --standalone -d grafikarsa.com -d www.grafikarsa.com

# Copy certificates
cp /etc/letsencrypt/live/grafikarsa.com/fullchain.pem ./nginx/ssl/
cp /etc/letsencrypt/live/grafikarsa.com/privkey.pem ./nginx/ssl/

# Start nginx
docker compose start nginx

# Auto-renewal (add to crontab)
0 0 1 * * certbot renew --pre-hook "docker compose stop nginx" --post-hook "docker compose start nginx"
```

---

## Monitoring & Logging

### Log Locations

| Service | Log Location |
|---------|--------------|
| Backend | `./logs/` (mounted volume) |
| Nginx | `docker logs grafikarsa-nginx` |
| PostgreSQL | `docker logs grafikarsa-postgres` |
| MinIO | `docker logs grafikarsa-minio` |

### Health Checks

```bash
# Backend health
curl http://localhost:8080/health

# PostgreSQL health
docker exec grafikarsa-postgres pg_isready

# MinIO health
curl http://localhost:9000/minio/health/live
```

### Simple Monitoring Script

```bash
#!/bin/bash
# scripts/health-check.sh

check_service() {
    if docker ps --format '{{.Names}}' | grep -q "$1"; then
        echo "✅ $1 is running"
    else
        echo "❌ $1 is NOT running"
        # Send alert (email, telegram, etc)
    fi
}

check_service "grafikarsa-backend"
check_service "grafikarsa-postgres"
check_service "grafikarsa-minio"
check_service "grafikarsa-nginx"
```

---

## Troubleshooting

### Common Issues

**1. Backend can't connect to PostgreSQL**
```bash
# Check if postgres is ready
docker logs grafikarsa-postgres

# Verify network
docker network inspect grafikarsa-network
```

**2. MinIO bucket not created**
```bash
# Run setup manually
docker compose up minio-setup
```

**3. File upload fails**
```bash
# Check MinIO logs
docker logs grafikarsa-minio

# Verify bucket permissions
docker exec grafikarsa-minio mc anonymous get local/grafikarsa
```

**4. Out of disk space**
```bash
# Check disk usage
df -h

# Clean Docker
docker system prune -a
```

**5. High memory usage**
```bash
# Check container stats
docker stats

# Restart specific servicepose restart backend
```

---

## Security Checklist

- [ ] Change all default passwords in `.env`
- [ ] Use strong JWT secrets (32+ characters)
- [ ] Enable SSL/HTTPS
- [ ] Configure firewall (only allow 80, 443, 22)
- [ ] Set up automated backups
- [ ] Enable fail2ban for SSH
- [ ] Regular security updates (`apt update && apt upgrade`)
- [ ] Don't expose PostgreSQL port (5432) to public
- [ ] Don't expose MinIO ports (9000, 9001) to public in production
- [ ] Use non-root user in containers
- [ ] Set resource limits in docker-compose
