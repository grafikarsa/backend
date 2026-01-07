# Deployment Guide: LXC (Proxmox) with Docker & Apache

This guide covers how to deploy the **Grafikarsa** application (Polyrepo) on a Proxmox LXC container running Ubuntu/Debian. The setup uses Docker for the application and Apache as a Reverse Proxy to handle Cloudflare domains.

## Prerequisites
- LXC Container (Ubuntu 22.04 / Debian 11 recommended)
- Docker & Docker Compose installed
- Apache installed (`sudo apt install apache2`)
- Cloudflare Domains pointed to your LXC Public IP

## 1. Directory Structure
On your LXC server, organize the project like this:
```
/opt/grafikarsa/
├── backend/            # Clone backend repo here
├── web/                # Clone web repo here
└── docker-compose.yml  # (Optional) Root orchestration if desired
```

## 2. Docker Setup

### Step 2.1: Network
Create the shared network manually to ensure it exists for both services.
```bash
docker network create grafikarsa-network
```

### Step 2.2: Backend
1.  Enter `backend` directory.
2.  Copy `.env.example` to `.env` and fill in production values.
    ```properties
    APP_ENV=production
    DB_PASSWORD=SecurePassword123!
    MINIO_SECRET_KEY=SecureMinioSecret!
    # Important: Use domain names here!
    STORAGE_PUBLIC_URL=https://storage.yourdomain.com/grafikarsa
    MINIO_PRESIGN_HOST=storage.yourdomain.com
    ```
3.  Start Connect services:
    ```bash
    docker-compose -f docker-compose.prod.yml up -d
    ```

### Step 2.3: Web
1.  Enter `web` directory.
2.  Copy `.env.example` to `.env` and configure:
    ```properties
    NODE_ENV=production
    # Browser Access (Public Domain)
    NEXT_PUBLIC_API_URL=https://api.yourdomain.com/api/v1
    NEXT_PUBLIC_APP_URL=https://yourdomain.com
    ```
3.  Start Web service:
    ```bash
    docker-compose -f docker-compose.prod.yml up -d
    ```

## 3. Apache Reverse Proxy Configuration

You will need to enable `mod_proxy`:
```bash
sudo a2enmod proxy proxy_http ssl headers
sudo systemctl restart apache2
```

Create a new config file: `/etc/apache2/sites-available/grafikarsa.conf`

**Replace `yourdomain.com` with your actual domain.**

```apache
# ==========================================
# 1. WEB APP (Next.js) -> Port 3000
# ==========================================
<VirtualHost *:80>
    ServerName yourdomain.com
    ServerAlias www.yourdomain.com

    ProxyPreserveHost On
    ProxyRequests Off

    # Proxy to Docker Container (localhost:3000)
    ProxyPass / http://localhost:3000/
    ProxyPassReverse / http://localhost:3000/

    ErrorLog ${APACHE_LOG_DIR}/grafikarsa-web-error.log
    CustomLog ${APACHE_LOG_DIR}/grafikarsa-web-access.log combined
</VirtualHost>

# ==========================================
# 2. BACKEND API -> Port 8080
# ==========================================
<VirtualHost *:80>
    ServerName api.yourdomain.com

    ProxyPreserveHost On
    ProxyRequests Off

    # Proxy to Docker Container (localhost:8080)
    ProxyPass / http://localhost:8080/
    ProxyPassReverse / http://localhost:8080/

    ErrorLog ${APACHE_LOG_DIR}/grafikarsa-api-error.log
    CustomLog ${APACHE_LOG_DIR}/grafikarsa-api-access.log combined
</VirtualHost>

# ==========================================
# 3. OBJECT STORAGE (MinIO) -> Port 9000
# ==========================================
<VirtualHost *:80>
    ServerName storage.yourdomain.com

    ProxyPreserveHost On
    ProxyRequests Off
    
    # Allow large uploads
    LimitRequestBody 0

    # Proxy to Docker Container (localhost:9000)
    ProxyPass / http://localhost:9000/
    ProxyPassReverse / http://localhost:9000/

    ErrorLog ${APACHE_LOG_DIR}/grafikarsa-storage-error.log
    CustomLog ${APACHE_LOG_DIR}/grafikarsa-storage-access.log combined
</VirtualHost>
```

### Enable Site
```bash
sudo a2ensite grafikarsa.conf
sudo systemctl reload apache2
```

## 4. Cloudflare SSL (SSL/TLS Encryption)

Since we configured Apache on port 80, changing Cloudflare settings is crucial:

1.  Go to Cloudflare Dashboard > **SSL/TLS**.
2.  Set mode to **Flexible** (Cloudflare talks HTTPS to user, but HTTP to your server).
    *   *Warning*: Flexible mode is easier but less secure between Cloudflare and you.
3.  **Better Option (Full SSL)**:
    - Set Cloudflare SSL to **Full (Strict)**.
    - Generate an **Origin Certificate** in Cloudflare.
    - Install that cert in Apache (`SSLCertificateFile` directive) and change `<VirtualHost *:80>` to `*:443`.
