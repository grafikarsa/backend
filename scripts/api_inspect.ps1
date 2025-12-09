# Grafikarsa API Inspector - Shows raw JSON request/response
# Usage: .\scripts\api_inspect.ps1 [-BaseUrl "http://localhost:8080"]

param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$Endpoint = "",
    [switch]$All
)

$ApiUrl = "$BaseUrl/api/v1"
$Global:AccessToken = ""
$Global:OutputLines = @()

# Setup log directory and file
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptDir "log"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Find next available log filename
$LogFile = Join-Path $LogDir "log.md"
if (Test-Path $LogFile) {
    $counter = 1
    while (Test-Path (Join-Path $LogDir "log$counter.md")) {
        $counter++
    }
    $LogFile = Join-Path $LogDir "log$counter.md"
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
    $Global:OutputLines += $Message
}

function Write-Header {
    param([string]$Title)
    Write-Log ""
    Write-Log ("=" * 80) -Color Cyan
    Write-Log "  $Title" -Color Cyan
    Write-Log ("=" * 80) -Color Cyan
}

function Write-SubHeader {
    param([string]$Title)
    Write-Log ""
    Write-Log ("-" * 60) -Color DarkGray
    Write-Log "  $Title" -Color Yellow
    Write-Log ("-" * 60) -Color DarkGray
}

function Format-Json {
    param([string]$Json)
    try {
        $obj = $Json | ConvertFrom-Json
        return $obj | ConvertTo-Json -Depth 10
    } catch {
        return $Json
    }
}

function Invoke-ApiInspect {
    param(
        [string]$Method,
        [string]$Endpoint,
        [hashtable]$Body = @{},
        [bool]$UseAuth = $false
    )
    
    $uri = "$ApiUrl$Endpoint"
    $headers = @{
        "Content-Type" = "application/json"
    }
    
    if ($UseAuth -and $Global:AccessToken) {
        $headers["Authorization"] = "Bearer $Global:AccessToken"
    }
    
    Write-SubHeader "$Method $Endpoint"
    
    # Show request
    Write-Log ""
    Write-Log "REQUEST:" -Color Green
    Write-Log "  URL: $uri" -Color Gray
    Write-Log "  Method: $Method" -Color Gray
    Write-Log "  Headers:" -Color Gray
    foreach ($key in $headers.Keys) {
        $value = $headers[$key]
        if ($key -eq "Authorization") {
            $value = "Bearer <token>"
        }
        Write-Log "    $key : $value" -Color Gray
    }
    
    if ($Body.Count -gt 0) {
        $bodyJson = $Body | ConvertTo-Json -Depth 5
        Write-Log "  Body:" -Color Gray
        Write-Log $bodyJson -Color DarkYellow
    }
    
    # Make request
    try {
        $params = @{
            Method = $Method
            Uri = $uri
            Headers = $headers
            ErrorAction = "Stop"
        }
        
        if ($Body.Count -gt 0 -and $Method -ne "GET") {
            $params["Body"] = ($Body | ConvertTo-Json -Depth 10)
        }
        
        $response = Invoke-WebRequest @params
        $statusCode = $response.StatusCode
        $content = $response.Content
        
        Write-Log ""
        Write-Log "RESPONSE:" -Color Green
        Write-Log "  Status: $statusCode" -Color $(if ($statusCode -lt 400) { "Green" } else { "Red" })
        Write-Log "  Body:" -Color Gray
        Write-Log (Format-Json $content)
        
        return @{
            StatusCode = $statusCode
            Content = $content | ConvertFrom-Json
        }
    }
    catch {
        $statusCode = 0
        $errorContent = ""
        
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorContent = $reader.ReadToEnd()
            } catch {}
        }
        
        Write-Log ""
        Write-Log "RESPONSE:" -Color Green
        Write-Log "  Status: $statusCode" -Color Red
        if ($errorContent) {
            Write-Log "  Body:" -Color Gray
            Write-Log (Format-Json $errorContent) -Color Red
        } else {
            Write-Log "  Error: $($_.Exception.Message)" -Color Red
        }
        
        return @{
            StatusCode = $statusCode
            Content = $null
        }
    }
}

function Login {
    $result = Invoke-ApiInspect -Method "POST" -Endpoint "/auth/login" -Body @{
        username = "admin"
        password = "password"
    }
    
    if ($result.Content -and $result.Content.data.access_token) {
        $Global:AccessToken = $result.Content.data.access_token
        Write-Log ""
        Write-Log "  [Logged in successfully, token saved]" -Color Green
    }
}

function Inspect-AllEndpoints {
    Write-Header "GRAFIKARSA API INSPECTOR"
    Write-Log "Base URL: $ApiUrl" -Color Magenta
    Write-Log "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Color Magenta
    
    # Check server
    try {
        $null = Invoke-WebRequest -Uri "$ApiUrl/health" -TimeoutSec 5 -ErrorAction Stop
    } catch {
        Write-Log "ERROR: Cannot connect to API server" -Color Red
        exit 1
    }
    
    # ========== PUBLIC ENDPOINTS ==========
    Write-Header "PUBLIC ENDPOINTS"
    
    Invoke-ApiInspect -Method "GET" -Endpoint "/jurusan"
    Invoke-ApiInspect -Method "GET" -Endpoint "/kelas"
    Invoke-ApiInspect -Method "GET" -Endpoint "/tags"
    Invoke-ApiInspect -Method "GET" -Endpoint "/users?limit=3"
    Invoke-ApiInspect -Method "GET" -Endpoint "/portfolios?limit=3"
    Invoke-ApiInspect -Method "GET" -Endpoint "/users/admin"
    Invoke-ApiInspect -Method "GET" -Endpoint "/users/admin/followers?limit=3"
    Invoke-ApiInspect -Method "GET" -Endpoint "/users/admin/following?limit=3"
    Invoke-ApiInspect -Method "GET" -Endpoint "/search/users?q=admin"
    Invoke-ApiInspect -Method "GET" -Endpoint "/search/portfolios?q=web"
    
    # ========== AUTHENTICATION ==========
    Write-Header "AUTHENTICATION"
    
    # Login invalid
    Invoke-ApiInspect -Method "POST" -Endpoint "/auth/login" -Body @{
        username = "invalid"
        password = "wrong"
    }
    
    # Login valid
    Login
    
    # ========== AUTHENTICATED ENDPOINTS ==========
    if ($Global:AccessToken) {
        Write-Header "PROFILE (AUTHENTICATED)"
        
        Invoke-ApiInspect -Method "GET" -Endpoint "/me" -UseAuth $true
        Invoke-ApiInspect -Method "GET" -Endpoint "/me/check-username?username=testuser123" -UseAuth $true
        Invoke-ApiInspect -Method "GET" -Endpoint "/me/portfolios?limit=3" -UseAuth $true
        
        Write-Header "FEED"
        Invoke-ApiInspect -Method "GET" -Endpoint "/feed?limit=3" -UseAuth $true
        
        Write-Header "SESSIONS"
        Invoke-ApiInspect -Method "GET" -Endpoint "/auth/sessions" -UseAuth $true
        
        Write-Header "ADMIN ENDPOINTS"
        Invoke-ApiInspect -Method "GET" -Endpoint "/admin/dashboard/stats" -UseAuth $true
        Invoke-ApiInspect -Method "GET" -Endpoint "/admin/users?limit=3" -UseAuth $true
        Invoke-ApiInspect -Method "GET" -Endpoint "/admin/jurusan" -UseAuth $true
        Invoke-ApiInspect -Method "GET" -Endpoint "/admin/tahun-ajaran" -UseAuth $true
        Invoke-ApiInspect -Method "GET" -Endpoint "/admin/kelas?limit=5" -UseAuth $true
        Invoke-ApiInspect -Method "GET" -Endpoint "/admin/tags" -UseAuth $true
        Invoke-ApiInspect -Method "GET" -Endpoint "/admin/portfolios?limit=3" -UseAuth $true
        Invoke-ApiInspect -Method "GET" -Endpoint "/admin/portfolios/pending?limit=3" -UseAuth $true
        
        Write-Header "PORTFOLIO CRUD DEMO"
        
        # Create portfolio
        $createResult = Invoke-ApiInspect -Method "POST" -Endpoint "/portfolios" -UseAuth $true -Body @{
            judul = "Demo Portfolio untuk Inspect"
        }
        
        if ($createResult.Content -and $createResult.Content.data.id) {
            $portfolioId = $createResult.Content.data.id
            
            # Get by ID
            Invoke-ApiInspect -Method "GET" -Endpoint "/portfolios/id/$portfolioId" -UseAuth $true
            
            # Update
            Invoke-ApiInspect -Method "PATCH" -Endpoint "/portfolios/$portfolioId" -UseAuth $true -Body @{
                judul = "Demo Portfolio Updated"
            }
            
            # Add content block
            $blockResult = Invoke-ApiInspect -Method "POST" -Endpoint "/portfolios/$portfolioId/blocks" -UseAuth $true -Body @{
                block_type = "text"
                block_order = 0
                payload = @{
                    content = "<p>Ini adalah content block demo</p>"
                }
            }
            
            if ($blockResult.Content -and $blockResult.Content.data.id) {
                $blockId = $blockResult.Content.data.id
                
                # Update block
                Invoke-ApiInspect -Method "PATCH" -Endpoint "/portfolios/$portfolioId/blocks/$blockId" -UseAuth $true -Body @{
                    payload = @{
                        content = "<p>Content block updated</p>"
                    }
                }
                
                # Delete block
                Invoke-ApiInspect -Method "DELETE" -Endpoint "/portfolios/$portfolioId/blocks/$blockId" -UseAuth $true
            }
            
            # Delete portfolio
            Invoke-ApiInspect -Method "DELETE" -Endpoint "/portfolios/$portfolioId" -UseAuth $true
        }
        
        Write-Header "LOGOUT"
        Invoke-ApiInspect -Method "POST" -Endpoint "/auth/logout" -UseAuth $true
    }
    
    Write-Log ""
    Write-Log ("=" * 80) -Color Cyan
    Write-Log "  INSPECTION COMPLETE" -Color Cyan
    Write-Log ("=" * 80) -Color Cyan
}

function Inspect-SingleEndpoint {
    param([string]$Path)
    
    Write-Header "SINGLE ENDPOINT INSPECTION"
    
    # Try to login first for authenticated endpoints
    $loginResult = Invoke-ApiInspect -Method "POST" -Endpoint "/auth/login" -Body @{
        username = "admin"
        password = "password"
    }
    
    if ($loginResult.Content -and $loginResult.Content.data.access_token) {
        $Global:AccessToken = $loginResult.Content.data.access_token
    }
    
    # Inspect the endpoint
    Invoke-ApiInspect -Method "GET" -Endpoint $Path -UseAuth ($Global:AccessToken -ne "")
}

# Main
if ($All -or $Endpoint -eq "") {
    Inspect-AllEndpoints
} else {
    Inspect-SingleEndpoint -Path $Endpoint
}

# Save output to log file
$mdContent = @"
# Grafikarsa API Inspection Log

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

``````
$($Global:OutputLines -join "`n")
``````
"@

$mdContent | Out-File -FilePath $LogFile -Encoding UTF8
Write-Host ""
Write-Host "Log saved to: $LogFile" -ForegroundColor Green
