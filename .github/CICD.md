# CI/CD Pipeline

This project uses GitHub Actions for Continuous Integration and Continuous Deployment.

## Workflows

### CI (Continuous Integration)
- **Trigger**: Push to `main`/`develop` branches, Pull Requests
- **Actions**: Go mod download, golangci-lint, Unit tests, Build

### CD (Continuous Deployment)
- **Trigger**: Push to `main` branch only
- **Actions**: Build Docker image, Push to Docker Hub, Deploy API to production

## Required GitHub Secrets

Configure these secrets in your GitHub repository settings:

| Secret | Description |
|--------|-------------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `SSH_HOST` | Production server IP/hostname |
| `SSH_USERNAME` | SSH username for deployment |
| `SSH_PRIVATE_KEY` | SSH private key content |
| `SSH_PORT` | SSH port (optional, default: 22) |

## Manual Deployment

If you need to deploy manually:

```bash
# On production server
cd /opt/grafikarsa/backend
docker pull <username>/grafikarsa-backend:latest

# Restart only API (keep DB and MinIO running)
docker-compose -f docker-compose.prod.yml stop api
docker-compose -f docker-compose.prod.yml rm -f api
docker-compose -f docker-compose.prod.yml up -d api
```

## Rollback

To rollback to a previous version:

```bash
# Find the commit SHA of the version you want
docker pull <username>/grafikarsa-backend:<commit-sha>

# Update and restart
export IMAGE_TAG=<commit-sha>
docker-compose -f docker-compose.prod.yml stop api
docker-compose -f docker-compose.prod.yml rm -f api
docker-compose -f docker-compose.prod.yml up -d api
```

## First-Time Setup

For initial deployment, you need to start all services:

```bash
cd /opt/grafikarsa/backend
cp .env.example .env
# Edit .env with production values

# Create Docker network
docker network create grafikarsa-network

# Start all services
docker-compose -f docker-compose.prod.yml up -d
```
