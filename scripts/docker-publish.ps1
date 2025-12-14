# =============================================================================
# GRAFIKARSA - Docker Hub Publish Script
# =============================================================================
# Usage: .\scripts\docker-publish.ps1 -Version "1.0.0"
#        .\scripts\docker-publish.ps1 -Version "1.0.0" -Username "yourusername"
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [string]$Username = "rafapradana",
    [string]$RepoName = "grafikarsa-api",
    [switch]$SkipLatest,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"
$BackendDir = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "GRAFIKARSA DOCKER PUBLISH" -ForegroundColor Magenta
Write-Host "=========================" -ForegroundColor Magenta
Write-Host ""

# Validate version format
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Host "ERROR: Version must be in format X.Y.Z (e.g., 1.0.0)" -ForegroundColor Red
    exit 1
}

$ImageName = "$Username/$RepoName"
$VersionTag = "${ImageName}:${Version}"
$LatestTag = "${ImageName}:latest"

Write-Host "Image Name: $ImageName" -ForegroundColor Cyan
Write-Host "Version Tag: $VersionTag" -ForegroundColor Cyan
if (-not $SkipLatest) {
    Write-Host "Latest Tag: $LatestTag" -ForegroundColor Cyan
}
Write-Host ""

# Change to backend directory
Set-Location $BackendDir

# Step 1: Build image
Write-Host "[1/3] Building Docker image..." -ForegroundColor Yellow
docker build -t $VersionTag .
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker build failed" -ForegroundColor Red
    exit 1
}
Write-Host "      Build successful!" -ForegroundColor Green

# Tag as latest
if (-not $SkipLatest) {
    Write-Host "[2/3] Tagging as latest..." -ForegroundColor Yellow
    docker tag $VersionTag $LatestTag
    Write-Host "      Tagged!" -ForegroundColor Green
} else {
    Write-Host "[2/3] Skipping latest tag" -ForegroundColor DarkGray
}

if ($BuildOnly) {
    Write-Host ""
    Write-Host "Build complete! (--BuildOnly flag set, skipping push)" -ForegroundColor Green
    Write-Host ""
    Write-Host "To push manually:" -ForegroundColor Cyan
    Write-Host "  docker push $VersionTag" -ForegroundColor White
    if (-not $SkipLatest) {
        Write-Host "  docker push $LatestTag" -ForegroundColor White
    }
    exit 0
}

# Step 3: Push to Docker Hub
Write-Host "[3/3] Pushing to Docker Hub..." -ForegroundColor Yellow

# Check if logged in
$loginCheck = docker info 2>&1 | Select-String "Username"
if (-not $loginCheck) {
    Write-Host "      You need to login to Docker Hub first" -ForegroundColor Yellow
    docker login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Docker login failed" -ForegroundColor Red
        exit 1
    }
}

# Push version tag
Write-Host "      Pushing $VersionTag..." -ForegroundColor Gray
docker push $VersionTag
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to push $VersionTag" -ForegroundColor Red
    exit 1
}

# Push latest tag
if (-not $SkipLatest) {
    Write-Host "      Pushing $LatestTag..." -ForegroundColor Gray
    docker push $LatestTag
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to push $LatestTag" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "SUCCESS! Image published to Docker Hub" -ForegroundColor Green
Write-Host ""
Write-Host "Pull command:" -ForegroundColor Cyan
Write-Host "  docker pull $VersionTag" -ForegroundColor White
Write-Host "  docker pull $LatestTag" -ForegroundColor White
Write-Host ""
Write-Host "Run command:" -ForegroundColor Cyan
Write-Host "  docker run -d -p 8080:8080 --env-file .env $LatestTag" -ForegroundColor White
Write-Host ""
