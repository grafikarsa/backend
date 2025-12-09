# Grafikarsa API Test Scripts

## Quick Start

### Option 1: Full Automated Setup & Test
```powershell
cd backend
.\scripts\run_tests.ps1
```

This will:
1. Start Docker services (PostgreSQL, MinIO)
2. Build the database CLI
3. Create database and run migrations
4. Seed sample data
5. Build and start the API server
6. Run all API tests
7. Stop the server

### Option 2: Manual Step-by-Step

1. Start Docker services:
```powershell
cd ..
docker-compose up -d postgres minio
cd backend
```

2. Setup database:
```powershell
go run ./cmd/dbcli
# Select: 1 (Create Database + Migrate)
# Select: 5 (Seed Data) -> 1 (Sedikit)
# Select: 0 (Exit)
```

3. Start API server (in separate terminal):
```powershell
go run ./cmd/api
```

4. Run tests:
```powershell
.\scripts\api_test.ps1
```

## Script Options

### run_tests.ps1
```powershell
# Full setup and test
.\scripts\run_tests.ps1

# Setup only (don't run tests)
.\scripts\run_tests.ps1 -SetupOnly

# Test only (assume server is running)
.\scripts\run_tests.ps1 -TestOnly

# Skip seeding data
.\scripts\run_tests.ps1 -SkipSeed
```

### api_test.ps1
```powershell
# Test against localhost:3000 (default)
.\scripts\api_test.ps1

# Test against different URL
.\scripts\api_test.ps1 -BaseUrl "http://localhost:8080"
```

## Test Coverage

The test script covers:

- **Public Endpoints**: /jurusan, /kelas, /tags, /users, /portfolios
- **Authentication**: login, logout, sessions
- **Profile**: GET/PATCH /me, check-username
- **Users**: profile, followers, following
- **Portfolios**: CRUD operations
- **Content Blocks**: create, update, delete
- **Social**: follow/unfollow, like/unlike
- **Feed & Search**: feed, search users/portfolios
- **Admin**: dashboard, users, jurusan, tahun-ajaran, kelas, tags, moderation

## Test Credentials

Default admin user (created by seeder):
- Username: `admin`
- Password: `password`

## Troubleshooting

### "Cannot connect to API server"
- Make sure the API server is running
- Check if port 3000 is available
- Verify .env configuration

### "Failed to build"
- Run `go mod tidy` to fix dependencies
- Check Go version (requires 1.21+)

### Database errors
- Ensure PostgreSQL is running: `docker ps`
- Check database connection in .env
- Try running dbcli with option 3 (Migrate Fresh)
