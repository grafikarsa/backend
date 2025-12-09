# Grafikarsa API Test Script
# Usage: .\scripts\api_test.ps1 [-BaseUrl "http://localhost:8080"]

param(
    [string]$BaseUrl = "http://localhost:8080"
)

$ApiUrl = "$BaseUrl/api/v1"
$Global:AccessToken = ""
$Global:RefreshToken = ""
$Global:TestUserId = ""
$Global:TestPortfolioId = ""
$Global:TestBlockId = ""
$Global:PassCount = 0
$Global:FailCount = 0
$Global:SkipCount = 0

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = "",
        [bool]$Skip = $false
    )
    
    if ($Skip) {
        Write-Host "[SKIP] $Name" -ForegroundColor Yellow
        if ($Message) { Write-Host "       $Message" -ForegroundColor Gray }
        $Global:SkipCount++
        return
    }
    
    if ($Success) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $Global:PassCount++
    } else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        if ($Message) { Write-Host "       $Message" -ForegroundColor Red }
        $Global:FailCount++
    }
}

function Invoke-ApiRequest {
    param(
        [string]$Method,
        [string]$Endpoint,
        [hashtable]$Body = @{},
        [hashtable]$Headers = @{},
        [bool]$UseAuth = $false,
        [int]$ExpectedStatus = 200
    )
    
    $uri = "$ApiUrl$Endpoint"
    $requestHeaders = @{
        "Content-Type" = "application/json"
    }
    
    foreach ($key in $Headers.Keys) {
        $requestHeaders[$key] = $Headers[$key]
    }
    
    if ($UseAuth -and $Global:AccessToken) {
        $requestHeaders["Authorization"] = "Bearer $Global:AccessToken"
    }
    
    try {
        $params = @{
            Method = $Method
            Uri = $uri
            Headers = $requestHeaders
            ErrorAction = "Stop"
        }
        
        if ($Body.Count -gt 0 -and $Method -ne "GET") {
            $params["Body"] = ($Body | ConvertTo-Json -Depth 10)
        }
        
        $response = Invoke-WebRequest @params
        $statusCode = $response.StatusCode
        $content = $response.Content | ConvertFrom-Json
        
        return @{
            Success = ($statusCode -eq $ExpectedStatus)
            StatusCode = $statusCode
            Data = $content
            Error = $null
        }
    }
    catch {
        $statusCode = 0
        $errorMessage = $_.Exception.Message
        
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorContent = $reader.ReadToEnd() | ConvertFrom-Json
                $errorMessage = $errorContent.error.message
            } catch {}
        }
        
        return @{
            Success = ($statusCode -eq $ExpectedStatus)
            StatusCode = $statusCode
            Data = $null
            Error = $errorMessage
        }
    }
}

# ============================================
# TEST SUITES
# ============================================

function Test-PublicEndpoints {
    Write-TestHeader "PUBLIC ENDPOINTS"
    
    # GET /jurusan
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/jurusan"
    Write-TestResult -Name "GET /jurusan" -Success $result.Success -Message $result.Error
    
    # GET /kelas
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/kelas"
    Write-TestResult -Name "GET /kelas" -Success $result.Success -Message $result.Error
    
    # GET /tags
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/tags"
    Write-TestResult -Name "GET /tags" -Success $result.Success -Message $result.Error
    
    # GET /users
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/users"
    Write-TestResult -Name "GET /users" -Success $result.Success -Message $result.Error
    
    # GET /portfolios
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/portfolios"
    Write-TestResult -Name "GET /portfolios" -Success $result.Success -Message $result.Error
}

function Test-AuthEndpoints {
    Write-TestHeader "AUTHENTICATION"
    
    # POST /auth/login - Invalid credentials
    $result = Invoke-ApiRequest -Method "POST" -Endpoint "/auth/login" -Body @{
        username = "invalid_user"
        password = "wrong_password"
    } -ExpectedStatus 401
    Write-TestResult -Name "POST /auth/login (invalid)" -Success $result.Success -Message $result.Error
    
    # POST /auth/login - Valid credentials
    $result = Invoke-ApiRequest -Method "POST" -Endpoint "/auth/login" -Body @{
        username = "admin"
        password = "password"
    }
    
    if ($result.Success -and $result.Data.data.access_token) {
        $Global:AccessToken = $result.Data.data.access_token
        Write-TestResult -Name "POST /auth/login (valid)" -Success $true
    } else {
        Write-TestResult -Name "POST /auth/login (valid)" -Success $false -Message "Failed to get access token: $($result.Error)"
    }
    
    # GET /auth/sessions
    if ($Global:AccessToken) {
        $result = Invoke-ApiRequest -Method "GET" -Endpoint "/auth/sessions" -UseAuth $true
        Write-TestResult -Name "GET /auth/sessions" -Success $result.Success -Message $result.Error
    } else {
        Write-TestResult -Name "GET /auth/sessions" -Skip $true -Message "No access token"
    }
}

function Test-ProfileEndpoints {
    Write-TestHeader "PROFILE (AUTHENTICATED)"
    
    if (-not $Global:AccessToken) {
        Write-TestResult -Name "Profile tests" -Skip $true -Message "No access token available"
        return
    }
    
    # GET /me
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/me" -UseAuth $true
    Write-TestResult -Name "GET /me" -Success $result.Success -Message $result.Error
    if ($result.Success) {
        $Global:TestUserId = $result.Data.data.id
    }
    
    # GET /me without auth (should fail)
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/me" -ExpectedStatus 401
    Write-TestResult -Name "GET /me (no auth)" -Success $result.Success -Message $result.Error
    
    # PATCH /me
    $result = Invoke-ApiRequest -Method "PATCH" -Endpoint "/me" -UseAuth $true -Body @{
        bio = "Updated bio from test script"
    }
    Write-TestResult -Name "PATCH /me" -Success $result.Success -Message $result.Error
    
    # GET /me/check-username
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/me/check-username?username=testuser123" -UseAuth $true
    Write-TestResult -Name "GET /me/check-username" -Success $result.Success -Message $result.Error
}

function Test-UserEndpoints {
    Write-TestHeader "USER ENDPOINTS"
    
    # GET /users/{username}
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/users/admin"
    Write-TestResult -Name "GET /users/{username}" -Success $result.Success -Message $result.Error
    
    # GET /users/{username} - Not found
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/users/nonexistent_user_12345" -ExpectedStatus 404
    Write-TestResult -Name "GET /users/{username} (404)" -Success $result.Success -Message $result.Error
    
    # GET /users/{username}/followers
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/users/admin/followers"
    Write-TestResult -Name "GET /users/{username}/followers" -Success $result.Success -Message $result.Error
    
    # GET /users/{username}/following
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/users/admin/following"
    Write-TestResult -Name "GET /users/{username}/following" -Success $result.Success -Message $result.Error
}

function Test-PortfolioEndpoints {
    Write-TestHeader "PORTFOLIO ENDPOINTS"
    
    if (-not $Global:AccessToken) {
        Write-TestResult -Name "Portfolio tests" -Skip $true -Message "No access token available"
        return
    }
    
    # POST /portfolios - Create
    $result = Invoke-ApiRequest -Method "POST" -Endpoint "/portfolios" -UseAuth $true -Body @{
        judul = "Test Portfolio from Script"
    } -ExpectedStatus 201
    
    if ($result.Success -and $result.Data.data.id) {
        $Global:TestPortfolioId = $result.Data.data.id
        Write-TestResult -Name "POST /portfolios" -Success $true
    } else {
        Write-TestResult -Name "POST /portfolios" -Success $false -Message $result.Error
    }
    
    # GET /me/portfolios
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/me/portfolios" -UseAuth $true
    Write-TestResult -Name "GET /me/portfolios" -Success $result.Success -Message $result.Error
    
    if ($Global:TestPortfolioId) {
        # GET /portfolios/id/{id} (note: route is /portfolios/id/:id to avoid conflict with slug)
        $result = Invoke-ApiRequest -Method "GET" -Endpoint "/portfolios/id/$Global:TestPortfolioId" -UseAuth $true
        Write-TestResult -Name "GET /portfolios/id/{id}" -Success $result.Success -Message $result.Error
        
        # PATCH /portfolios/{id}
        $result = Invoke-ApiRequest -Method "PATCH" -Endpoint "/portfolios/$Global:TestPortfolioId" -UseAuth $true -Body @{
            judul = "Updated Test Portfolio"
        }
        Write-TestResult -Name "PATCH /portfolios/{id}" -Success $result.Success -Message $result.Error
    }
}

function Test-ContentBlockEndpoints {
    Write-TestHeader "CONTENT BLOCK ENDPOINTS"
    
    if (-not $Global:AccessToken -or -not $Global:TestPortfolioId) {
        Write-TestResult -Name "Content block tests" -Skip $true -Message "No portfolio available"
        return
    }
    
    # POST /portfolios/{id}/blocks
    $result = Invoke-ApiRequest -Method "POST" -Endpoint "/portfolios/$Global:TestPortfolioId/blocks" -UseAuth $true -Body @{
        block_type = "text"
        block_order = 0
        payload = @{
            content = "<p>Test content block</p>"
        }
    } -ExpectedStatus 201
    
    if ($result.Success -and $result.Data.data.id) {
        $Global:TestBlockId = $result.Data.data.id
        Write-TestResult -Name "POST /portfolios/{id}/blocks" -Success $true
    } else {
        Write-TestResult -Name "POST /portfolios/{id}/blocks" -Success $false -Message $result.Error
    }
    
    if ($Global:TestBlockId) {
        # PATCH /portfolios/{id}/blocks/{block_id}
        $result = Invoke-ApiRequest -Method "PATCH" -Endpoint "/portfolios/$Global:TestPortfolioId/blocks/$Global:TestBlockId" -UseAuth $true -Body @{
            payload = @{
                content = "<p>Updated content</p>"
            }
        }
        Write-TestResult -Name "PATCH /portfolios/{id}/blocks/{block_id}" -Success $result.Success -Message $result.Error
        
        # DELETE /portfolios/{id}/blocks/{block_id}
        $result = Invoke-ApiRequest -Method "DELETE" -Endpoint "/portfolios/$Global:TestPortfolioId/blocks/$Global:TestBlockId" -UseAuth $true
        Write-TestResult -Name "DELETE /portfolios/{id}/blocks/{block_id}" -Success $result.Success -Message $result.Error
    }
}

function Test-SocialEndpoints {
    Write-TestHeader "SOCIAL ENDPOINTS (FOLLOW/LIKE)"
    
    if (-not $Global:AccessToken) {
        Write-TestResult -Name "Social tests" -Skip $true -Message "No access token available"
        return
    }
    
    # Get a user to follow (not admin)
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/users?limit=5"
    $targetUser = $null
    if ($result.Success -and $result.Data.data) {
        foreach ($user in $result.Data.data) {
            if ($user.username -ne "admin") {
                $targetUser = $user.username
                break
            }
        }
    }
    
    if ($targetUser) {
        # POST /users/{username}/follow
        $result = Invoke-ApiRequest -Method "POST" -Endpoint "/users/$targetUser/follow" -UseAuth $true
        Write-TestResult -Name "POST /users/{username}/follow" -Success ($result.Success -or $result.StatusCode -eq 409) -Message $result.Error
        
        # DELETE /users/{username}/follow
        $result = Invoke-ApiRequest -Method "DELETE" -Endpoint "/users/$targetUser/follow" -UseAuth $true
        Write-TestResult -Name "DELETE /users/{username}/follow" -Success ($result.Success -or $result.StatusCode -eq 400) -Message $result.Error
    } else {
        Write-TestResult -Name "Follow tests" -Skip $true -Message "No other users to follow"
    }
    
    # Get a portfolio to like
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/portfolios?limit=1"
    if ($result.Success -and $result.Data.data -and $result.Data.data.Count -gt 0) {
        $portfolioId = $result.Data.data[0].id
        
        # POST /portfolios/{id}/like
        $result = Invoke-ApiRequest -Method "POST" -Endpoint "/portfolios/$portfolioId/like" -UseAuth $true
        Write-TestResult -Name "POST /portfolios/{id}/like" -Success ($result.Success -or $result.StatusCode -eq 409) -Message $result.Error
        
        # DELETE /portfolios/{id}/like
        $result = Invoke-ApiRequest -Method "DELETE" -Endpoint "/portfolios/$portfolioId/like" -UseAuth $true
        Write-TestResult -Name "DELETE /portfolios/{id}/like" -Success ($result.Success -or $result.StatusCode -eq 400) -Message $result.Error
    } else {
        Write-TestResult -Name "Like tests" -Skip $true -Message "No portfolios to like"
    }
}

function Test-FeedEndpoints {
    Write-TestHeader "FEED & SEARCH"
    
    # GET /feed (requires auth)
    if ($Global:AccessToken) {
        $result = Invoke-ApiRequest -Method "GET" -Endpoint "/feed" -UseAuth $true
        Write-TestResult -Name "GET /feed" -Success $result.Success -Message $result.Error
    } else {
        Write-TestResult -Name "GET /feed" -Skip $true -Message "No access token"
    }
    
    # GET /search/users
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/search/users?q=admin"
    Write-TestResult -Name "GET /search/users" -Success $result.Success -Message $result.Error
    
    # GET /search/portfolios
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/search/portfolios?q=test"
    Write-TestResult -Name "GET /search/portfolios" -Success $result.Success -Message $result.Error
}

function Test-AdminEndpoints {
    Write-TestHeader "ADMIN ENDPOINTS"
    
    if (-not $Global:AccessToken) {
        Write-TestResult -Name "Admin tests" -Skip $true -Message "No access token available"
        return
    }
    
    # GET /admin/dashboard/stats
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/admin/dashboard/stats" -UseAuth $true
    Write-TestResult -Name "GET /admin/dashboard/stats" -Success $result.Success -Message $result.Error
    
    # GET /admin/users
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/admin/users" -UseAuth $true
    Write-TestResult -Name "GET /admin/users" -Success $result.Success -Message $result.Error
    
    # GET /admin/jurusan
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/admin/jurusan" -UseAuth $true
    Write-TestResult -Name "GET /admin/jurusan" -Success $result.Success -Message $result.Error
    
    # GET /admin/tahun-ajaran
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/admin/tahun-ajaran" -UseAuth $true
    Write-TestResult -Name "GET /admin/tahun-ajaran" -Success $result.Success -Message $result.Error
    
    # GET /admin/kelas
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/admin/kelas" -UseAuth $true
    Write-TestResult -Name "GET /admin/kelas" -Success $result.Success -Message $result.Error
    
    # GET /admin/tags
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/admin/tags" -UseAuth $true
    Write-TestResult -Name "GET /admin/tags" -Success $result.Success -Message $result.Error
    
    # GET /admin/portfolios/pending
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/admin/portfolios/pending" -UseAuth $true
    Write-TestResult -Name "GET /admin/portfolios/pending" -Success $result.Success -Message $result.Error
    
    # GET /admin/portfolios
    $result = Invoke-ApiRequest -Method "GET" -Endpoint "/admin/portfolios" -UseAuth $true
    Write-TestResult -Name "GET /admin/portfolios" -Success $result.Success -Message $result.Error
}

function Test-Cleanup {
    Write-TestHeader "CLEANUP"
    
    if ($Global:TestPortfolioId -and $Global:AccessToken) {
        $result = Invoke-ApiRequest -Method "DELETE" -Endpoint "/portfolios/$Global:TestPortfolioId" -UseAuth $true
        Write-TestResult -Name "DELETE test portfolio" -Success $result.Success -Message $result.Error
    }
}

function Test-Logout {
    Write-TestHeader "LOGOUT"
    
    if ($Global:AccessToken) {
        $result = Invoke-ApiRequest -Method "POST" -Endpoint "/auth/logout" -UseAuth $true
        Write-TestResult -Name "POST /auth/logout" -Success $result.Success -Message $result.Error
    }
}

# ============================================
# MAIN
# ============================================

Write-Host ""
Write-Host "GRAFIKARSA API TEST SUITE" -ForegroundColor Magenta
Write-Host "Base URL: $ApiUrl" -ForegroundColor Magenta
Write-Host ""

# Check if server is running
try {
    $null = Invoke-WebRequest -Uri "$ApiUrl/tags" -TimeoutSec 5 -ErrorAction Stop
} catch {
    Write-Host "ERROR: Cannot connect to API server at $ApiUrl" -ForegroundColor Red
    Write-Host "Make sure the server is running: go run ./cmd/api" -ForegroundColor Yellow
    exit 1
}

# Run tests
Test-PublicEndpoints
Test-AuthEndpoints
Test-ProfileEndpoints
Test-UserEndpoints
Test-PortfolioEndpoints
Test-ContentBlockEndpoints
Test-SocialEndpoints
Test-FeedEndpoints
Test-AdminEndpoints
Test-Cleanup
Test-Logout

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "PASSED: $Global:PassCount" -ForegroundColor Green
Write-Host "FAILED: $Global:FailCount" -ForegroundColor Red
Write-Host "SKIPPED: $Global:SkipCount" -ForegroundColor Yellow
Write-Host ""

$total = $Global:PassCount + $Global:FailCount
if ($total -gt 0) {
    $percentage = [math]::Round(($Global:PassCount / $total) * 100, 1)
    Write-Host "Success Rate: $percentage%" -ForegroundColor $(if ($percentage -ge 80) { "Green" } elseif ($percentage -ge 50) { "Yellow" } else { "Red" })
}

if ($Global:FailCount -gt 0) {
    exit 1
}
