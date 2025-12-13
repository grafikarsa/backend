-- ============================================================================
-- Seed Data: Feedback
-- Sample feedback data untuk testing
-- ============================================================================

-- Catatan: Jalankan setelah ada user di database
-- Ganti user_id dengan UUID user yang valid

-- Sample feedback dari user yang login
INSERT INTO feedback (kategori, pesan, status, user_id) VALUES
('bug', 'Halaman portfolio kadang loading lama saat banyak gambar. Mungkin bisa ditambahkan lazy loading?', 'pending', (SELECT id FROM users WHERE username = 'ahmadnug77' LIMIT 1)),
('saran', 'Bagus kalau ada fitur untuk export portfolio ke PDF, biar bisa dikirim ke perusahaan saat melamar kerja.', 'read', (SELECT id FROM users WHERE username = 'ahmadnug77' LIMIT 1)),
('saran', 'Tolong tambahkan dark mode yang lebih gelap lagi, yang sekarang masih agak terang.', 'resolved', (SELECT id FROM users WHERE username = 'ahmadnug77' LIMIT 1)),
('bug', 'Tombol like kadang tidak responsif di mobile, harus tap berkali-kali.', 'pending', (SELECT id FROM users WHERE username = 'ahmadnug77' LIMIT 1)),
('lainnya', 'Website ini sangat membantu untuk showcase karya kami. Terima kasih tim Grafikarsa!', 'read', (SELECT id FROM users WHERE username = 'ahmadnug77' LIMIT 1));

-- Sample feedback dari guest (tanpa user_id)
INSERT INTO feedback (kategori, pesan, status) VALUES
('saran', 'Sebagai pengunjung, saya berharap ada fitur search yang lebih canggih dengan filter berdasarkan jurusan.', 'pending'),
('bug', 'Ada typo di halaman about, tulisan "SMKN 4 Malang" tertulis "SMKN 4 Malan".', 'resolved'),
('lainnya', 'Desain websitenya bagus dan modern. Cocok untuk anak SMK jurusan multimedia.', 'read');

-- Update admin_notes untuk yang sudah resolved
UPDATE feedback SET admin_notes = 'Sudah ditambahkan lazy loading untuk gambar di versi 1.2.0' WHERE pesan LIKE '%lazy loading%' AND status = 'resolved';
UPDATE feedback SET admin_notes = 'Typo sudah diperbaiki. Terima kasih laporannya!' WHERE pesan LIKE '%typo%' AND status = 'resolved';
UPDATE feedback SET admin_notes = 'Dark mode sudah diperbarui dengan opsi "Darker" di settings.' WHERE pesan LIKE '%dark mode%' AND status = 'resolved';
