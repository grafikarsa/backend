# Deployment Guide: Grafikarsa

Panduan lengkap untuk deploy aplikasi Grafikarsa (Backend + Frontend) dari server Ubuntu baru hingga CI/CD berjalan otomatis.

---

## 📋 Arsitektur

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLOUDFLARE                                │
│   domain.com ──► api.domain.com ──► storage.domain.com          │
└───────────────────────────┬─────────────────────────────────────┘
                            │ (HTTPS)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    UBUNTU SERVER                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  APACHE (Port 80)                        │    │
│  │   /           → localhost:3000 (Web)                     │    │
│  │   api.        → localhost:8080 (Backend API)             │    │
│  │   storage.    → localhost:9000 (MinIO)                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                            │                                     │
│  ┌─────────────────────────┴───────────────────────────────┐    │
│  │                   DOCKER CONTAINERS                      │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │    │
│  │  │   Web    │ │ Backend  │ │ Postgres │ │  MinIO   │    │    │
│  │  │  :3000   │ │  :8080   │ │  :5432   │ │  :9000   │    │    │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔧 BAGIAN 1: Setup Server Baru (Fresh Ubuntu)

### 1.1 Update System
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git nano ufw
```

### 1.2 Install Docker
```bash
# Install Docker Engine
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose plugin
sudo apt install -y docker-compose-plugin

# Verifikasi
docker --version
docker compose version
```

### 1.3 Setup Firewall
```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status
```

### 1.4 Buat User Deployment
```bash
# Buat user 'deploy'
sudo adduser deploy
# Ikuti prompt, set password

# Beri akses Docker
sudo usermod -aG docker deploy

# Buat direktori project
sudo mkdir -p /opt/grafikarsa/web
sudo mkdir -p /opt/grafikarsa/backend
sudo chown -R deploy:deploy /opt/grafikarsa
```

### 1.5 Buat Docker Network
```bash
docker network create grafikarsa-network
```

---

## 🔑 BAGIAN 2: Setup SSH Key untuk CI/CD

### 2.1 Generate SSH Key (Di Komputer Lokal)
Buka terminal di laptop/PC Anda:
```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f github_deploy
```
Tekan Enter terus (kosongkan passphrase).

Akan terbuat 2 file:
- `github_deploy` → **Private Key** (untuk GitHub Secret)
- `github_deploy.pub` → **Public Key** (untuk server)

### 2.2 Copy Public Key ke Server
```bash
# Tampilkan public key
cat github_deploy.pub
```
Copy output-nya.

Di server, sebagai user deploy:
```bash
su - deploy
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
# Paste public key, save (Ctrl+O, Enter, Ctrl+X)
chmod 600 ~/.ssh/authorized_keys
exit
```

### 2.3 Test Koneksi SSH
```bash
ssh -i github_deploy deploy@IP_SERVER_ANDA
```
Jika berhasil masuk, berarti SSH key sudah benar.

---

## 🐳 BAGIAN 3: Setup Docker Hub

### 3.1 Buat Akun Docker Hub
1. Buka [hub.docker.com](https://hub.docker.com/)
2. Sign up / Login

### 3.2 Buat Access Token
1. Klik profile → **Account Settings**
2. Tab **Security** → **New Access Token**
3. Description: `github-actions`
4. Permissions: **Read & Write**
5. **COPY TOKEN** (hanya muncul sekali!)

---

## ⚙️ BAGIAN 4: Setup GitHub Secrets

Buka **KEDUA** repository (web dan backend) di GitHub.

Pergi ke: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

### Secrets yang Diperlukan:

| Secret Name | Deskripsi | Contoh Value |
|-------------|-----------|--------------|
| `DOCKERHUB_USERNAME` | Username Docker Hub | `rafapradana` |
| `DOCKERHUB_TOKEN` | Access Token Docker Hub | `dckr_pat_xxxx` |
| `SSH_HOST` | IP Server Ubuntu | `103.123.45.67` |
| `SSH_USERNAME` | User untuk deploy | `deploy` |
| `SSH_PRIVATE_KEY` | Isi file `github_deploy` (LENGKAP) | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `SSH_PORT` | Port SSH (opsional) | `22` |

### Secrets Tambahan untuk Repo Web:

| Secret Name | Deskripsi | Contoh Value |
|-------------|-----------|--------------|
| `NEXT_PUBLIC_API_URL` | URL Backend API | `https://api.domain.com/api/v1` |
| `NEXT_PUBLIC_APP_URL` | URL Frontend | `https://domain.com` |

---

## 🚀 BAGIAN 5: First Deployment (Manual)

Untuk deployment pertama kali, harus manual karena belum ada image di Docker Hub.

### 5.1 Setup Backend

SSH ke server sebagai user `deploy`:
```bash
ssh deploy@IP_SERVER
cd /opt/grafikarsa/backend
```

Buat file `docker-compose.prod.yml`:
```bash
nano docker-compose.prod.yml
```

Paste isi berikut:
```yaml
services:
  api:
    image: ${DOCKERHUB_USERNAME}/grafikarsa-backend:${IMAGE_TAG:-latest}
    container_name: grafikarsa-backend
    restart: unless-stopped
    ports:
      - "8080:8080"
    env_file:
      - .env
    environment:
      - APP_ENV=production
      - DB_HOST=db
      - DB_PORT=5432
      - MINIO_ENDPOINT=minio:9000
    depends_on:
      db:
        condition: service_healthy
      minio:
        condition: service_healthy
    networks:
      - grafikarsa-network

  db:
    image: postgres:15-alpine
    container_name: grafikarsa-db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=${DB_NAME}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - grafikarsa-network

  minio:
    image: minio/minio:latest
    container_name: grafikarsa-minio
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      - MINIO_ROOT_USER=${MINIO_ACCESS_KEY}
      - MINIO_ROOT_PASSWORD=${MINIO_SECRET_KEY}
    volumes:
      - minio_data:/data
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 5s
      timeout: 5s
      retries: 10
    networks:
      - grafikarsa-network

volumes:
  postgres_data:
  minio_data:

networks:
  grafikarsa-network:
    external: true
```

Buat file `.env`:
```bash
nano .env
```

Isi dengan:
```properties
# Docker Hub
DOCKERHUB_USERNAME=your_dockerhub_username

# Database
DB_USER=grafikarsa
DB_PASSWORD=YourSecureDBPassword123!
DB_NAME=grafikarsa

# MinIO
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=YourSecureMinioPassword123!
MINIO_BUCKET=grafikarsa

# JWT
JWT_SECRET=your-super-secret-jwt-key-at-least-32-characters-long
JWT_ACCESS_EXPIRY=15m
JWT_REFRESH_EXPIRY=168h

# CORS
CORS_ORIGINS=https://domain.com,https://www.domain.com

# Storage
STORAGE_PUBLIC_URL=https://storage.domain.com/grafikarsa
```

### 5.2 Push Image Pertama dari Lokal

Di komputer lokal Anda, build dan push image:

**Backend:**
```bash
cd path/to/grafikarsa/backend
docker login
docker build -t YOUR_DOCKERHUB_USERNAME/grafikarsa-backend:latest .
docker push YOUR_DOCKERHUB_USERNAME/grafikarsa-backend:latest
```

**Web:**
```bash
cd path/to/grafikarsa/web
docker build \
  --build-arg NEXT_PUBLIC_API_URL=https://api.domain.com/api/v1 \
  --build-arg NEXT_PUBLIC_APP_URL=https://domain.com \
  -t YOUR_DOCKERHUB_USERNAME/grafikarsa-web:latest .
docker push YOUR_DOCKERHUB_USERNAME/grafikarsa-web:latest
```

### 5.3 Start Services di Server

**Backend:**
```bash
cd /opt/grafikarsa/backend
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

**Web:**
```bash
cd /opt/grafikarsa/web
nano docker-compose.prod.yml
```

Isi:
```yaml
services:
  web:
    image: ${DOCKERHUB_USERNAME}/grafikarsa-web:${IMAGE_TAG:-latest}
    container_name: grafikarsa-web
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    networks:
      - grafikarsa-network

networks:
  grafikarsa-network:
    external: true
```

Buat `.env`:
```bash
echo "DOCKERHUB_USERNAME=your_dockerhub_username" > .env
```

Start:
```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

### 5.4 Verifikasi
```bash
docker ps
# Harus muncul: grafikarsa-web, grafikarsa-backend, grafikarsa-db, grafikarsa-minio

curl http://localhost:8080/health
curl http://localhost:3000
```

---

## 🌐 BAGIAN 6: Setup Apache Reverse Proxy

### 6.1 Install Apache
```bash
sudo apt install -y apache2
sudo a2enmod proxy proxy_http headers rewrite
```

### 6.2 Buat Config
```bash
sudo nano /etc/apache2/sites-available/grafikarsa.conf
```

Isi:
```apache
# Frontend (domain.com)
<VirtualHost *:80>
    ServerName domain.com
    ServerAlias www.domain.com

    ProxyPreserveHost On
    ProxyPass / http://localhost:3000/
    ProxyPassReverse / http://localhost:3000/

    ErrorLog ${APACHE_LOG_DIR}/web-error.log
    CustomLog ${APACHE_LOG_DIR}/web-access.log combined
</VirtualHost>

# Backend API (api.domain.com)
<VirtualHost *:80>
    ServerName api.domain.com

    ProxyPreserveHost On
    ProxyPass / http://localhost:8080/
    ProxyPassReverse / http://localhost:8080/

    ErrorLog ${APACHE_LOG_DIR}/api-error.log
    CustomLog ${APACHE_LOG_DIR}/api-access.log combined
</VirtualHost>

# Storage MinIO (storage.domain.com)
<VirtualHost *:80>
    ServerName storage.domain.com

    ProxyPreserveHost On
    LimitRequestBody 0
    ProxyPass / http://localhost:9000/
    ProxyPassReverse / http://localhost:9000/

    ErrorLog ${APACHE_LOG_DIR}/storage-error.log
    CustomLog ${APACHE_LOG_DIR}/storage-access.log combined
</VirtualHost>
```

### 6.3 Enable Site
```bash
sudo a2ensite grafikarsa.conf
sudo systemctl reload apache2
```

---

## ☁️ BAGIAN 7: Setup Cloudflare

### 7.1 DNS Records
Di Cloudflare Dashboard → DNS → Records, tambahkan:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `@` | IP_SERVER | 🟠 Proxied |
| A | `api` | IP_SERVER | 🟠 Proxied |
| A | `storage` | IP_SERVER | 🟠 Proxied |
| A | `www` | IP_SERVER | 🟠 Proxied |

### 7.2 SSL/TLS Settings
1. **SSL/TLS → Overview**: Pilih **Flexible**
2. **SSL/TLS → Edge Certificates**: Enable **Always Use HTTPS**

---

## 🔄 BAGIAN 8: Cara Menggunakan CI/CD

Setelah semua setup selesai, CI/CD akan berjalan **OTOMATIS**.

### Cara Kerja:

```
Push ke main → GitHub Actions → Build Docker → Push ke Hub → Deploy ke Server
```

### Yang Perlu Anda Lakukan:

1. **Edit code** di komputer lokal
2. **Commit** perubahan:
   ```bash
   git add .
   git commit -m "feat: add new feature"
   ```
3. **Push** ke branch `main`:
   ```bash
   git push origin main
   ```
4. **Selesai!** GitHub Actions akan otomatis:
   - Build Docker image
   - Push ke Docker Hub
   - SSH ke server
   - Pull image terbaru
   - Restart container

### Monitoring:
- Buka tab **Actions** di GitHub repository
- ✅ Hijau = Sukses
- ❌ Merah = Gagal (klik untuk lihat error)

### Melihat Logs di Server:
```bash
ssh deploy@IP_SERVER
docker logs grafikarsa-backend -f --tail=100
docker logs grafikarsa-web -f --tail=100
```

---

## 🔙 Rollback ke Versi Sebelumnya

Jika ada masalah, rollback ke versi sebelumnya:

```bash
# 1. Cari commit SHA yang diinginkan di Docker Hub atau GitHub

# 2. Di server:
cd /opt/grafikarsa/backend
export IMAGE_TAG=abc1234  # ganti dengan commit SHA
docker compose -f docker-compose.prod.yml pull api
docker compose -f docker-compose.prod.yml up -d api
```

---

## 🛠️ Troubleshooting

### Container tidak start
```bash
docker compose -f docker-compose.prod.yml logs
```

### SSH Connection Refused
- Cek firewall: `sudo ufw status`
- Cek SSH service: `sudo systemctl status ssh`

### Permission Denied (SSH)
- Pastikan public key ada di `~/.ssh/authorized_keys`
- Pastikan private key di GitHub Secret lengkap (termasuk header/footer)

### Docker Pull Failed
- Cek `DOCKERHUB_USERNAME` dan `DOCKERHUB_TOKEN` di GitHub Secrets
- Pastikan image sudah di-push ke Docker Hub

---

## 📝 Checklist Deployment

- [ ] Server: Docker & Docker Compose installed
- [ ] Server: User `deploy` dengan akses Docker
- [ ] Server: Docker network `grafikarsa-network` created
- [ ] Server: Firewall allows port 80, 443, 22
- [ ] Local: SSH key generated
- [ ] Server: Public key di `authorized_keys`
- [ ] GitHub: All secrets configured (kedua repo)
- [ ] Docker Hub: Access token created
- [ ] Server: Backend `.env` configured
- [ ] Server: docker-compose.prod.yml files created
- [ ] Server: Apache configured
- [ ] Cloudflare: DNS records added
- [ ] Cloudflare: SSL mode = Flexible
- [ ] First push ke main branch
- [ ] GitHub Actions: CI/CD workflow passed
