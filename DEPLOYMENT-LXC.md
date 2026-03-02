# Deployment Guide: Grafikarsa di LXC Ubuntu 22.04

Panduan lengkap untuk deploy aplikasi Grafikarsa (Backend + Frontend) di LXC Container Ubuntu 22.04 dengan Docker nesting enabled.

---

## 📋 Arsitektur LXC

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLOUDFLARE                                │
│   domain.com ──► api.domain.com ──► storage.domain.com          │
└───────────────────────────┬─────────────────────────────────────┘
                            │ (HTTPS)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PROXMOX HOST                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              LXC CONTAINER (Ubuntu 22.04)                  │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │              APACHE (Port 80)                        │  │  │
│  │  │   /           → localhost:3000 (Web)                 │  │  │
│  │  │   api.        → localhost:8080 (Backend API)         │  │  │
│  │  │   storage.    → localhost:9000 (MinIO)               │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                          │                                 │  │
│  │  ┌───────────────────────┴───────────────────────────┐    │  │
│  │  │               DOCKER CONTAINERS                    │    │  │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐  │    │  │
│  │  │  │   Web    │ │ Backend  │ │ Postgres │ │MinIO │  │    │  │
│  │  │  │  :3000   │ │  :8080   │ │  :5432   │ │:9000 │  │    │  │
│  │  │  └──────────┘ └──────────┘ └──────────┘ └──────┘  │    │  │
│  │  └───────────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔧 BAGIAN 0: Setup LXC Container di Proxmox

### 0.1 Buat LXC Container (Di Proxmox Host)

```bash
# Login ke Proxmox host via SSH atau web shell

# Buat container Ubuntu 22.04
pct create 100 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname grafikarsa \
  --memory 4096 \
  --cores 2 \
  --rootfs local-lvm:20 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --password \
  --unprivileged 1 \
  --features nesting=1

# Atau via Proxmox Web UI:
# 1. Create CT → Ubuntu 22.04 template
# 2. Resources: 2 CPU, 4GB RAM, 20GB disk
# 3. Network: Bridge vmbr0, DHCP
# 4. Options → Features → Enable "Nesting"
```

### 0.2 Start Container
```bash
pct start 100
```

### 0.3 Login ke Container
```bash
pct enter 100
# atau
ssh root@IP_LXC
```

---

## 🔧 BAGIAN 1: Setup LXC Container (Fresh Ubuntu 22.04)

### 1.1 Update System
```bash
apt update && apt upgrade -y
apt install -y curl git nano ca-certificates gnupg lsb-release
```

### 1.2 Install Docker di LXC

**PENTING**: LXC dengan nesting memerlukan instalasi Docker khusus.

```bash
# Install Docker dari official repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Verifikasi
docker --version
docker compose version
```

### 1.3 Fix Docker di LXC (Jika Ada Error)

Jika Docker tidak bisa start, jalankan:

```bash
# Edit Docker daemon config
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "storage-driver": "overlay2",
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF

# Restart Docker
systemctl restart docker
systemctl enable docker

# Test
docker run hello-world
```

### 1.4 Buat User Deployment
```bash
# Buat user 'deploy'
adduser deploy
# Set password saat diminta

# Beri akses Docker
usermod -aG docker deploy

# Buat direktori project
mkdir -p /opt/grafikarsa/web
mkdir -p /opt/grafikarsa/backend
chown -R deploy:deploy /opt/grafikarsa

# Test user deploy
su - deploy
docker ps
exit
```

### 1.5 Buat Docker Network
```bash
docker network create grafikarsa-network
```

---

## 🔑 BAGIAN 2: Setup SSH Key untuk CI/CD

### 2.1 Generate SSH Key (Di Komputer Lokal Windows)

Buka PowerShell atau Git Bash:
```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f github_deploy
```
Tekan Enter terus (kosongkan passphrase).

Akan terbuat 2 file:
- `github_deploy` → **Private Key** (untuk GitHub Secret)
- `github_deploy.pub` → **Public Key** (untuk LXC)

### 2.2 Copy Public Key ke LXC

```bash
# Tampilkan public key
cat github_deploy.pub
# atau di Windows PowerShell:
type github_deploy.pub
```
Copy output-nya.

Di LXC, sebagai user deploy:
```bash
su - deploy
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
# Paste public key, save (Ctrl+O, Enter, Ctrl+X)
chmod 600 ~/.ssh/authorized_keys
exit
```

### 2.3 Enable SSH di LXC (Jika Belum)
```bash
apt install -y openssh-server
systemctl enable ssh
systemctl start ssh

# Cek status
systemctl status ssh
```

### 2.4 Test Koneksi SSH
Dari komputer lokal:
```bash
ssh -i github_deploy deploy@IP_LXC
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
| `SSH_HOST` | IP LXC Container | `192.168.1.100` |
| `SSH_USERNAME` | User untuk deploy | `deploy` |
| `SSH_PRIVATE_KEY` | Isi file `github_deploy` (LENGKAP) | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `SSH_PORT` | Port SSH | `22` |

### Secrets Tambahan untuk Repo Web:

| Secret Name | Deskripsi | Contoh Value |
|-------------|-----------|--------------|
| `NEXT_PUBLIC_API_URL` | URL Backend API | `https://api.domain.com/api/v1` |
| `NEXT_PUBLIC_APP_URL` | URL Frontend | `https://domain.com` |

---

## 🚀 BAGIAN 5: First Deployment (Manual)

### 5.1 Setup Backend

SSH ke LXC sebagai user `deploy`:
```bash
ssh deploy@IP_LXC
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

Di komputer lokal Anda (Windows), buka PowerShell/Terminal:

**Backend:**
```bash
cd C:\Users\inven\Documents\rafa\grafika\grafikarsa\backend
docker login
docker build -t YOUR_DOCKERHUB_USERNAME/grafikarsa-backend:latest .
docker push YOUR_DOCKERHUB_USERNAME/grafikarsa-backend:latest
```

**Web:**
```bash
cd C:\Users\inven\Documents\rafa\grafika\grafikarsa\web
docker build `
  --build-arg NEXT_PUBLIC_API_URL=https://api.domain.com/api/v1 `
  --build-arg NEXT_PUBLIC_APP_URL=https://domain.com `
  -t YOUR_DOCKERHUB_USERNAME/grafikarsa-web:latest .
docker push YOUR_DOCKERHUB_USERNAME/grafikarsa-web:latest
```

### 5.3 Start Services di LXC

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

## 💾 BAGIAN 5.5: Setup Database Schema

### 5.5.1 Copy File SQL ke LXC

Dari komputer lokal (Windows PowerShell):
```powershell
scp -i github_deploy backend/docs/db/db.sql deploy@IP_LXC:/opt/grafikarsa/backend/
```

### 5.5.2 Import SQL ke Database

Di LXC (SSH sebagai user `deploy`):
```bash
cd /opt/grafikarsa/backend

# Import schema ke database grafikarsa
docker exec -i grafikarsa-db psql -U grafikarsa -d grafikarsa < db.sql

# Verifikasi
docker exec -it grafikarsa-db psql -U grafikarsa -d grafikarsa -c "\dt"
```

---

## 🌐 BAGIAN 6: Setup Apache Reverse Proxy

### 6.1 Install Apache
```bash
# Sebagai root
apt install -y apache2
a2enmod proxy proxy_http headers rewrite ssl
```

### 6.2 Buat Config
```bash
nano /etc/apache2/sites-available/grafikarsa.conf
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

    # WebSocket support untuk Next.js HMR (development)
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://localhost:3000/$1" [P,L]

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
    
    # MinIO requires these headers
    RequestHeader set X-Forwarded-Proto "https"
    
    ProxyPass / http://localhost:9000/
    ProxyPassReverse / http://localhost:9000/

    ErrorLog ${APACHE_LOG_DIR}/storage-error.log
    CustomLog ${APACHE_LOG_DIR}/storage-access.log combined
</VirtualHost>
```

### 6.3 Enable Site
```bash
a2ensite grafikarsa.conf
a2dissite 000-default.conf
systemctl reload apache2
systemctl enable apache2
```

### 6.4 Test Apache Config
```bash
apache2ctl configtest
# Harus output: Syntax OK
```

---

## 🔌 BAGIAN 7: Setup Port Forwarding di Proxmox (Opsional)

Jika LXC menggunakan IP private dan ingin diakses dari luar:

### 7.1 Di Proxmox Host

```bash
# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Port forwarding (ganti IP_PROXMOX dan IP_LXC)
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 80 -j DNAT --to IP_LXC:80
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 443 -j DNAT --to IP_LXC:443
iptables -t nat -A POSTROUTING -s IP_LXC -j MASQUERADE

# Save rules
apt install -y iptables-persistent
netfilter-persistent save
```

---

## ☁️ BAGIAN 8: Setup Cloudflare

### 8.1 DNS Records

Di Cloudflare Dashboard → DNS → Records, tambahkan:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `@` | IP_PROXMOX_atau_IP_LXC | 🟠 Proxied |
| A | `api` | IP_PROXMOX_atau_IP_LXC | 🟠 Proxied |
| A | `storage` | IP_PROXMOX_atau_IP_LXC | 🟠 Proxied |
| A | `www` | IP_PROXMOX_atau_IP_LXC | 🟠 Proxied |

### 8.2 SSL/TLS Settings
1. **SSL/TLS → Overview**: Pilih **Flexible**
2. **SSL/TLS → Edge Certificates**: Enable **Always Use HTTPS**

---

## 🔄 BAGIAN 9: Cara Menggunakan CI/CD

Setelah semua setup selesai, CI/CD akan berjalan **OTOMATIS**.

### Cara Kerja:

```
Push ke main → GitHub Actions → Build Docker → Push ke Hub → Deploy ke LXC
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
   - SSH ke LXC
   - Pull image terbaru
   - Restart container

### Monitoring:
- Buka tab **Actions** di GitHub repository
- ✅ Hijau = Sukses
- ❌ Merah = Gagal (klik untuk lihat error)

### Melihat Logs di LXC:
```bash
ssh deploy@IP_LXC
docker logs grafikarsa-backend -f --tail=100
docker logs grafikarsa-web -f --tail=100
```

---

## 🔙 Rollback ke Versi Sebelumnya

Jika ada masalah, rollback ke versi sebelumnya:

```bash
# 1. Cari commit SHA yang diinginkan di Docker Hub atau GitHub

# 2. Di LXC:
cd /opt/grafikarsa/backend
export IMAGE_TAG=abc1234  # ganti dengan commit SHA
docker compose -f docker-compose.prod.yml pull api
docker compose -f docker-compose.prod.yml up -d api
```

---

## 🛠️ Troubleshooting

### Docker tidak bisa start di LXC
```bash
# Cek nesting enabled
pct config 100 | grep features
# Harus ada: features: nesting=1

# Jika belum, enable dari Proxmox host:
pct set 100 -features nesting=1
pct reboot 100
```

### Container tidak start
```bash
docker compose -f docker-compose.prod.yml logs
docker ps -a
```

### SSH Connection Refused
```bash
# Cek SSH service
systemctl status ssh
systemctl restart ssh

# Cek dari Proxmox host
pct enter 100
```

### Permission Denied (SSH)
```bash
# Pastikan public key ada
cat ~/.ssh/authorized_keys

# Pastikan permission benar
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### Docker Pull Failed
```bash
# Test koneksi Docker Hub
docker login

# Cek DNS
cat /etc/docker/daemon.json
# Harus ada: "dns": ["8.8.8.8", "8.8.4.4"]
```

### Apache tidak bisa start
```bash
# Cek config
apache2ctl configtest

# Cek port conflict
netstat -tulpn | grep :80

# Restart
systemctl restart apache2
```

### Database connection failed
```bash
# Cek container running
docker ps | grep postgres

# Test koneksi
docker exec -it grafikarsa-db psql -U grafikarsa -d grafikarsa

# Cek logs
docker logs grafikarsa-db
```

### MinIO tidak bisa upload
```bash
# Cek logs
docker logs grafikarsa-minio

# Cek bucket
docker exec -it grafikarsa-minio mc ls local/

# Buat bucket manual jika perlu
docker exec -it grafikarsa-minio mc mb local/grafikarsa
docker exec -it grafikarsa-minio mc anonymous set download local/grafikarsa
```

---

## 💾 Backup & Restore

### Backup Database
```bash
# Backup
docker exec grafikarsa-db pg_dump -U grafikarsa grafikarsa > backup_$(date +%Y%m%d).sql

# Restore
docker exec -i grafikarsa-db psql -U grafikarsa -d grafikarsa < backup_20240101.sql
```

### Backup MinIO Data
```bash
# Backup
docker run --rm \
  -v grafikarsa_minio_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/minio_backup_$(date +%Y%m%d).tar.gz /data

# Restore
docker run --rm \
  -v grafikarsa_minio_data:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/minio_backup_20240101.tar.gz -C /
```

### Backup LXC Container (Di Proxmox Host)
```bash
# Backup full container
vzdump 100 --mode snapshot --compress zstd --storage local

# Restore
pct restore 101 /var/lib/vz/dump/vzdump-lxc-100-*.tar.zst
```

---

## 📊 Monitoring

### Resource Usage
```bash
# CPU & Memory
docker stats

# Disk usage
df -h
docker system df

# Logs size
du -sh /var/lib/docker/containers/*
```

### Clean Up
```bash
# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune

# Remove unused networks
docker network prune

# Clean all
docker system prune -a --volumes
```

---

## 📝 Checklist Deployment

- [ ] Proxmox: LXC container created dengan nesting=1
- [ ] LXC: Docker & Docker Compose installed
- [ ] LXC: User `deploy` dengan akses Docker
- [ ] LXC: Docker network `grafikarsa-network` created
- [ ] LXC: SSH server installed dan running
- [ ] Local: SSH key generated
- [ ] LXC: Public key di `authorized_keys`
- [ ] GitHub: All secrets configured (kedua repo)
- [ ] Docker Hub: Access token created
- [ ] LXC: Backend `.env` configured
- [ ] LXC: docker-compose.prod.yml files created
- [ ] LXC: Database schema imported
- [ ] LXC: Apache configured dan running
- [ ] Proxmox: Port forwarding configured (jika perlu)
- [ ] Cloudflare: DNS records added
- [ ] Cloudflare: SSL mode = Flexible
- [ ] First push ke main branch
- [ ] GitHub Actions: CI/CD workflow passed
- [ ] Test: Web accessible via domain.com
- [ ] Test: API accessible via api.domain.com
- [ ] Test: Storage accessible via storage.domain.com

---

## 🎯 Quick Commands Reference

```bash
# SSH ke LXC
ssh deploy@IP_LXC

# Restart semua services
cd /opt/grafikarsa/backend && docker compose -f docker-compose.prod.yml restart
cd /opt/grafikarsa/web && docker compose -f docker-compose.prod.yml restart

# View logs
docker logs -f grafikarsa-backend
docker logs -f grafikarsa-web
docker logs -f grafikarsa-db
docker logs -f grafikarsa-minio

# Check status
docker ps
systemctl status apache2

# Update deployment
cd /opt/grafikarsa/backend
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d

# Database access
docker exec -it grafikarsa-db psql -U grafikarsa -d grafikarsa

# MinIO console
# Buka browser: http://IP_LXC:9001
# Login dengan MINIO_ACCESS_KEY dan MINIO_SECRET_KEY
```

---

## 🚀 Next Steps

Setelah deployment berhasil:

1. Setup monitoring (Prometheus + Grafana)
2. Setup automated backups (cron jobs)
3. Configure log rotation
4. Setup alerts (email/Telegram)
5. Implement rate limiting
6. Add CDN untuk static assets
7. Setup staging environment

---

**Selamat! Aplikasi Grafikarsa sudah running di LXC Ubuntu 22.04** 🎉
