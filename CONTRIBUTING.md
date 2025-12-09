# Contributing to Grafikarsa Backend

Terima kasih atas minat Anda untuk berkontribusi pada project Grafikarsa!

## Sebelum Berkontribusi

Project ini bersifat **proprietary** dan hanya menerima kontribusi dari kontributor yang telah disetujui. Jika Anda ingin berkontribusi, silakan hubungi maintainer terlebih dahulu.

## Contact

Maintainer: rafapradana.com@gmail.com

## Code Style

- Gunakan `gofmt` untuk formatting
- Ikuti [Effective Go](https://golang.org/doc/effective_go) guidelines
- Tulis komentar untuk fungsi publik
- Gunakan nama variabel yang deskriptif

## Commit Messages

Format: `<type>: <description>`

Types:
- `feat`: Fitur baru
- `fix`: Bug fix
- `docs`: Dokumentasi
- `refactor`: Refactoring
- `test`: Testing
- `chore`: Maintenance

Contoh:
```
feat: add portfolio like endpoint
fix: resolve JWT refresh token issue
docs: update API documentation
```

## Pull Request

1. Fork repository (jika diizinkan)
2. Buat branch baru: `git checkout -b feat/nama-fitur`
3. Commit changes
4. Push ke branch
5. Buat Pull Request

## Testing

Pastikan semua test pass sebelum submit PR:

```powershell
.\scripts\api_test.ps1
```
