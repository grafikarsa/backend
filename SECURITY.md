# Security Policy

## Reporting a Vulnerability

Jika Anda menemukan kerentanan keamanan pada project ini, mohon **JANGAN** membuat public issue.

Silakan laporkan secara privat ke:
- Email: rafapradana.com@gmail.com

Kami akan merespons dalam waktu 48 jam dan bekerja sama dengan Anda untuk memahami dan mengatasi masalah tersebut.

## Security Best Practices

### Environment Variables

- Jangan pernah commit file `.env` ke repository
- Gunakan secret yang kuat untuk `JWT_ACCESS_SECRET` dan `JWT_REFRESH_SECRET` (minimal 32 karakter)
- Rotasi secret secara berkala di production

### Database

- Gunakan user database dengan privilege minimal
- Aktifkan SSL untuk koneksi database di production
- Backup database secara berkala

### API

- Semua endpoint sensitif memerlukan autentikasi
- Rate limiting diaktifkan untuk mencegah abuse
- CORS dikonfigurasi dengan whitelist origin yang spesifik

### JWT

- Access token memiliki expiry pendek (15 menit default)
- Refresh token disimpan di HttpOnly cookie
- Token blacklist untuk logout dan revocation
- Token family tracking untuk deteksi reuse attack

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
