# Grafikarsa Backend

REST API Backend untuk Platform Katalog Portofolio & Social Network Warga SMKN 4 Malang.

## Tech Stack

- **Language:** Go 1.21+
- **Framework:** GoFiber v2
- **Database:** PostgreSQL 15+
- **Object Storage:** MinIO
- **Authentication:** JWT (Access + Refresh Token)

## Features

- User authentication dengan dual-token JWT
- Portfolio management dengan modular content blocks
- Social features (follow/unfollow, like)
- Admin panel untuk moderasi
- File upload via MinIO presigned URLs
- Full-text search

## Quick Start

### Prerequisites

- Go 1.21+
- Docker & Docker Compose
- PostgreSQL 15+ (atau via Docker)
- MinIO (atau via Docker)

### Development Setup

1. Clone repository:
```bash
git clone https://github.com/grafikarsa/backend.git
cd backend
```

2. Copy environment file:
```bash
cp .env.example .env
```

3. Start dependencies via Docker:
```bash
docker-compose up -d postgres minio createbuckets
```

4. Setup database:
```bash
go run ./cmd/dbcli
# Pilih 1: Buat Database + Migrasi Schema
# Pilih 5: Seed Data (opsional)
```

5. Run API server:
```bash
go run ./cmd/api
```

Server akan berjalan di `http://localhost:8080`

### Using Docker Compose (Full Stack)

```bash
docker-compose up -d
```

## Project Structure

```
backend/
├── cmd/
│   ├── api/          # Main API server
│   └── dbcli/        # Database CLI tool
├── internal/
│   ├── auth/         # JWT service
│   ├── config/       # Configuration
│   ├── database/     # Database connection
│   ├── domain/       # Domain models
│   ├── dto/          # Data transfer objects
│   ├── handler/      # HTTP handlers
│   ├── middleware/   # Middleware (auth, etc)
│   ├── repository/   # Data access layer
│   └── storage/      # MinIO client
├── docs/             # Documentation
├── scripts/          # Test & utility scripts
├── Dockerfile
├── docker-compose.yml
└── go.mod
```

## API Documentation

Lihat [docs/api.md](docs/api.md) untuk dokumentasi lengkap API.

## Testing

### Run API Tests

```powershell
# Windows PowerShell
.\scripts\api_test.ps1
```

### Inspect API Responses

```powershell
# Lihat raw JSON request/response
.\scripts\api_inspect.ps1
```

## Database CLI

Tool untuk mengelola database:

```bash
go run ./cmd/dbcli
```

Menu:
1. Buat Database + Migrasi Schema
2. Migrasi Schema (tanpa buat database)
3. Migrate Fresh (drop semua + migrasi ulang)
4. Truncate Tables (kecuali reference data)
5. Seed Data (generate dummy data)
6. Hapus Database

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| APP_ENV | Environment (development/production) | development |
| APP_PORT | Server port | 8080 |
| DB_HOST | PostgreSQL host | localhost |
| DB_PORT | PostgreSQL port | 5432 |
| DB_USER | PostgreSQL user | postgres |
| DB_PASSWORD | PostgreSQL password | - |
| DB_NAME | Database name | grafikarsa |
| MINIO_ENDPOINT | MinIO endpoint | localhost:9000 |
| MINIO_ACCESS_KEY | MinIO access key | - |
| MINIO_SECRET_KEY | MinIO secret key | - |
| MINIO_BUCKET | MinIO bucket name | grafikarsa |
| JWT_ACCESS_SECRET | JWT access token secret | - |
| JWT_REFRESH_SECRET | JWT refresh token secret | - |
| JWT_ACCESS_EXPIRY | Access token expiry | 15m |
| JWT_REFRESH_EXPIRY | Refresh token expiry | 168h |

## Deployment

### Docker

```bash
docker build -t grafikarsa-backend .
docker run -p 8080:8080 --env-file .env grafikarsa-backend
```

### Manual

```bash
go build -o grafikarsa-api ./cmd/api
./grafikarsa-api
```

## Contributing

Project ini bersifat proprietary. Untuk kontribusi, hubungi maintainer.

## License

All Rights Reserved. Lihat [LICENSE](LICENSE) untuk detail.

## Contact

Maintainer: rafapradana.com@gmail.com
