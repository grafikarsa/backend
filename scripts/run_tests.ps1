# Quick Start Script for Grafikarsa API Testing
# This script helps you set up and test the API

param(
    [switch]$SetupOnly,
    [switch]$TestOnly,
    [switch]$SkipSeed
)

$ErrorActionPreference = "Stop"
$BackendDir = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "GRAFIKARSA API SETUP & TEST" -ForegroundColor Magenta
Write-Host "============================" -ForegroundColor Magenta
Write-Host ""

# Check if we're in the right directory
if (-not (Test-Path "$BackendDir\go.mod")) {
    Write-Host "ERROR: Please run this script from the backend directory" -ForegroundColor Red
    exit 1
}

Set-Location $BackendDir

if (-not $TestOnly) {
    # Step 1: Check Docker
    Write-Host "[1/5] Checking Docker..." -ForegroundColor Cyan
    try {
        $null = docker --version
        Write-Host "      Docker is available" -ForegroundColor Green
    } catch {
        Write-Host "      ERROR: Docker is not installed or not running" -ForegroundColor Red
        exit 1
    }

    # Step 2: Start Docker services
    Write-Host "[2/5] Starting Docker services (PostgreSQL, MinIO)..." -ForegroundColor Cyan
    Set-Location ..
    docker-compose up -d postgres minio 2>$null
    if ($LASTEXITCODE -ne 0) {
        # Try with docker compose (v2)
        docker compose up -d postgres minio
    }
    Set-Location $BackendDir
    Write-Host "      Waiting for services to be ready..." -ForegroundColor Gray
    Start-Sleep -Seconds 5

    # Step 3: Build dbcli
    Write-Host "[3/5] Building database CLI..." -ForegroundColor Cyan
    go build -o bin/dbcli.exe ./cmd/dbcli
    if ($LASTEXITCODE -ne 0) {
        Write-Host "      ERROR: Failed to build dbcli" -ForegroundColor Red
        exit 1
    }
    Write-Host "      Built successfully" -ForegroundColor Green

    # Step 4: Setup database
    Write-Host "[4/5] Setting up database..." -ForegroundColor Cyan
    
    # Run dbcli with input
    $dbcliInput = @"
1
y
"@
    
    if (-not $SkipSeed) {
        $dbcliInput += @"

5
1

"@
    }
    
    $dbcliInput += "0`n"
    
    $dbcliInput | .\bin\dbcli.exe
    Write-Host "      Database setup complete" -ForegroundColor Green

    # Step 5: Build API
    Write-Host "[5/5] Building API server..." -ForegroundColor Cyan
    go build -o bin/api.exe ./cmd/api
    if ($LASTEXITCODE -ne 0) {
        Write-Host "      ERROR: Failed to build API" -ForegroundColor Red
        exit 1
    }
    Write-Host "      Built successfully" -ForegroundColor Green
}

if ($SetupOnly) {
    Write-Host ""
    Write-Host "Setup complete! To start the API server, run:" -ForegroundColor Green
    Write-Host "  .\bin\api.exe" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Then run tests with:" -ForegroundColor Green
    Write-Host "  .\scripts\api_test.ps1" -ForegroundColor Yellow
    exit 0
}

# Start API server in background
Write-Host ""
Write-Host "Starting API server..." -ForegroundColor Cyan
$apiProcess = Start-Process -FilePath ".\bin\api.exe" -PassThru -WindowStyle Hidden
Write-Host "API server started (PID: $($apiProcess.Id))" -ForegroundColor Green
Write-Host "Waiting for server to be ready..." -ForegroundColor Gray
Start-Sleep -Seconds 3

# Run tests
Write-Host ""
Write-Host "Running API tests..." -ForegroundColor Cyan
Write-Host ""

try {
    & "$PSScriptRoot\api_test.ps1"
    $testResult = $LASTEXITCODE
} finally {
    # Stop API server
    Write-Host ""
    Write-Host "Stopping API server..." -ForegroundColor Cyan
    Stop-Process -Id $apiProcess.Id -Force -ErrorAction SilentlyContinue
    Write-Host "API server stopped" -ForegroundColor Green
}

exit $testResult
