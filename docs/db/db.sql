-- ============================================================================
-- GRAFIKARSA DATABASE SCHEMA
-- Platform Katalog Portofolio & Social Network Warga SMKN 4 Malang
-- PostgreSQL 15+
-- ============================================================================
-- 
-- KEPUTUSAN DESAIN UTAMA:
-- 
-- 1. NORMALISASI (BCNF):
--    - Setiap tabel memiliki single-purpose dan tidak ada transitive dependency.
--    - Social links dipisah ke tabel tersendiri (user_social_links) untuk fleksibilitas
--      penambahan platform baru tanpa alter schema.
--    - Histori kelas siswa disimpan di tabel terpisah (student_class_history) untuk
--      menjaga riwayat lengkap tanpa redundansi.
--
-- 2. SCALABILITY:
--    - UUID sebagai primary key untuk distributed system compatibility.
--    - Proper indexing pada kolom yang sering di-query (username, email, slug, status).
--    - Partisi-ready design untuk tabel besar (portfolios, content_blocks).
--    - Soft delete pattern dengan deleted_at untuk data recovery.
--
-- 3. KEAMANAN JWT:
--    - Tabel refresh_tokens terpisah dengan device tracking dan revocation support.
--    - Token family tracking untuk mendeteksi token reuse attack.
--    - Automatic cleanup via expires_at untuk token hygiene.
--    - Password hash disimpan terpisah dari data user untuk query optimization.
--
-- 4. FLEKSIBILITAS:
--    - JSONB untuk content block payload (schema-less untuk berbagai tipe konten).
--    - Enum types untuk status dan role agar type-safe namun extensible.
--    - Trigger untuk auto-generate nama kelas dan slug.
--
-- ============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- untuk fuzzy search

-- ============================================================================
-- ENUM TYPES
-- ============================================================================

CREATE TYPE user_role AS ENUM ('student', 'alumni', 'admin');
CREATE TYPE portfolio_status AS ENUM ('draft', 'pending_review', 'rejected', 'published', 'archived');
CREATE TYPE content_block_type AS ENUM ('text', 'image', 'table', 'youtube', 'button', 'embed');
CREATE TYPE social_platform AS ENUM (
    'facebook', 'instagram', 'github', 'linkedin', 'twitter',
    'personal_website', 'tiktok', 'youtube', 'behance', 'dribbble',
    'threads', 'bluesky', 'medium', 'gitlab'
);

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Jurusan (Department/Major)
CREATE TABLE jurusan (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nama VARCHAR(100) NOT NULL,
    kode VARCHAR(10) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    
    CONSTRAINT jurusan_kode_lowercase CHECK (kode = LOWER(kode)),
    CONSTRAINT jurusan_kode_alpha CHECK (kode ~ '^[a-z]+$')
);

CREATE INDEX idx_jurusan_kode ON jurusan(kode) WHERE deleted_at IS NULL;

COMMENT ON TABLE jurusan IS 'Master data jurusan/program keahlian';
COMMENT ON COLUMN jurusan.kode IS 'Kode jurusan lowercase, hanya huruf (contoh: rpl, tkj, mm)';

-- Tahun Ajaran (Academic Year)
CREATE TABLE tahun_ajaran (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tahun_mulai INTEGER NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    promotion_month SMALLINT NOT NULL DEFAULT 7,
    promotion_day SMALLINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    
    CONSTRAINT tahun_ajaran_tahun_valid CHECK (tahun_mulai >= 2000 AND tahun_mulai <= 2100),
    CONSTRAINT tahun_ajaran_promotion_month_valid CHECK (promotion_month BETWEEN 1 AND 12),
    CONSTRAINT tahun_ajaran_promotion_day_valid CHECK (promotion_day BETWEEN 1 AND 31)
);

CREATE UNIQUE INDEX idx_tahun_ajaran_active ON tahun_ajaran(is_active) 
    WHERE is_active = TRUE AND deleted_at IS NULL;

COMMENT ON TABLE tahun_ajaran IS 'Master data tahun ajaran untuk tracking kelas per periode';
COMMENT ON COLUMN tahun_ajaran.is_active IS 'Hanya satu tahun ajaran yang boleh aktif';
COMMENT ON COLUMN tahun_ajaran.promotion_month IS 'Bulan kenaikan kelas otomatis (1-12)';
COMMENT ON COLUMN tahun_ajaran.promotion_day IS 'Tanggal kenaikan kelas otomatis (1-31)';

-- Kelas (Class)
CREATE TABLE kelas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tahun_ajaran_id UUID NOT NULL REFERENCES tahun_ajaran(id) ON DELETE RESTRICT,
    jurusan_id UUID NOT NULL REFERENCES jurusan(id) ON DELETE RESTRICT,
    tingkat SMALLINT NOT NULL,
    rombel CHAR(1) NOT NULL,
    nama VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    
    CONSTRAINT kelas_tingkat_valid CHECK (tingkat IN (10, 11, 12)),
    CONSTRAINT kelas_rombel_valid CHECK (rombel ~ '^[A-Z]$'),
    CONSTRAINT kelas_unique_per_tahun UNIQUE (tahun_ajaran_id, jurusan_id, tingkat, rombel)
);

CREATE INDEX idx_kelas_tahun_ajaran ON kelas(tahun_ajaran_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_kelas_jurusan ON kelas(jurusan_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_kelas_nama ON kelas(nama) WHERE deleted_at IS NULL;

COMMENT ON TABLE kelas IS 'Data kelas per tahun ajaran';
COMMENT ON COLUMN kelas.tingkat IS 'Tingkat kelas: 10, 11, atau 12';
COMMENT ON COLUMN kelas.rombel IS 'Rombongan belajar: A-Z';
COMMENT ON COLUMN kelas.nama IS 'Nama kelas auto-generated: X-RPL-A, XI-MM-B, dst';

-- Tags
CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nama VARCHAR(50) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_tags_nama ON tags(nama) WHERE deleted_at IS NULL;

COMMENT ON TABLE tags IS 'Master data tags untuk kategorisasi portofolio';

-- ============================================================================
-- USER & AUTHENTICATION
-- ============================================================================

-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(30) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    nama VARCHAR(100) NOT NULL,
    bio TEXT,
    avatar_url TEXT,
    banner_url TEXT,
    role user_role NOT NULL DEFAULT 'student',
    
    -- Student-specific fields (nullable for non-students)
    nisn VARCHAR(20),
    nis VARCHAR(30),
    kelas_id UUID REFERENCES kelas(id) ON DELETE SET NULL,
    tahun_masuk INTEGER,
    tahun_lulus INTEGER,
    
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    
    CONSTRAINT users_nisn_numeric CHECK (nisn IS NULL OR nisn ~ '^\d+$'),
    CONSTRAINT users_tahun_masuk_valid CHECK (tahun_masuk IS NULL OR (tahun_masuk >= 2000 AND tahun_masuk <= 2100)),
    CONSTRAINT users_tahun_lulus_valid CHECK (tahun_lulus IS NULL OR tahun_lulus >= tahun_masuk)
);

CREATE INDEX idx_users_username ON users(username) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_email ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_role ON users(role) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_kelas ON users(kelas_id) WHERE deleted_at IS NULL AND kelas_id IS NOT NULL;
CREATE INDEX idx_users_nama_trgm ON users USING gin(nama gin_trgm_ops) WHERE deleted_at IS NULL;

COMMENT ON TABLE users IS 'Data user (student, alumni, admin)';
COMMENT ON COLUMN users.password_hash IS 'Bcrypt hashed password';
COMMENT ON COLUMN users.kelas_id IS 'Kelas saat ini (untuk student aktif)';

-- User Social Links (normalized)
CREATE TABLE user_social_links (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform social_platform NOT NULL,
    url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT user_social_links_unique UNIQUE (user_id, platform)
);

CREATE INDEX idx_user_social_links_user ON user_social_links(user_id);

COMMENT ON TABLE user_social_links IS 'Social media links user (dinormalisasi untuk fleksibilitas)';

-- Student Class History (untuk tracking riwayat kelas)
CREATE TABLE student_class_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kelas_id UUID NOT NULL REFERENCES kelas(id) ON DELETE RESTRICT,
    tahun_ajaran_id UUID NOT NULL REFERENCES tahun_ajaran(id) ON DELETE RESTRICT,
    is_current BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT student_class_history_unique UNIQUE (user_id, kelas_id, tahun_ajaran_id)
);

CREATE INDEX idx_student_class_history_user ON student_class_history(user_id);
CREATE INDEX idx_student_class_history_current ON student_class_history(user_id, is_current) WHERE is_current = TRUE;

COMMENT ON TABLE student_class_history IS 'Riwayat kelas siswa per tahun ajaran';

-- ============================================================================
-- JWT REFRESH TOKEN MANAGEMENT
-- ============================================================================

CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    family_id UUID NOT NULL,
    device_info JSONB,
    ip_address INET,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at TIMESTAMPTZ,
    revoked_reason VARCHAR(100),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id) WHERE is_revoked = FALSE;
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash) WHERE is_revoked = FALSE;
CREATE INDEX idx_refresh_tokens_family ON refresh_tokens(family_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at) WHERE is_revoked = FALSE;

COMMENT ON TABLE refresh_tokens IS 'JWT refresh tokens dengan rotation dan revocation support';
COMMENT ON COLUMN refresh_tokens.token_hash IS 'SHA-256 hash dari refresh token (token asli tidak disimpan)';
COMMENT ON COLUMN refresh_tokens.family_id IS 'Token family untuk deteksi reuse attack';
COMMENT ON COLUMN refresh_tokens.device_info IS 'Info device: user_agent, device_type, dll';

-- Token Blacklist (untuk access token yang perlu di-revoke sebelum expire)
CREATE TABLE token_blacklist (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    jti VARCHAR(64) NOT NULL UNIQUE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    blacklisted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reason VARCHAR(100)
);

CREATE INDEX idx_token_blacklist_jti ON token_blacklist(jti);
CREATE INDEX idx_token_blacklist_expires ON token_blacklist(expires_at);

COMMENT ON TABLE token_blacklist IS 'Blacklist untuk access token yang di-revoke sebelum expire';
COMMENT ON COLUMN token_blacklist.jti IS 'JWT ID (unique identifier per token)';

-- ============================================================================
-- SOCIAL FEATURES
-- ============================================================================

-- Follows (user following system)
CREATE TABLE follows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT follows_no_self_follow CHECK (follower_id != following_id),
    CONSTRAINT follows_unique UNIQUE (follower_id, following_id)
);

CREATE INDEX idx_follows_follower ON follows(follower_id);
CREATE INDEX idx_follows_following ON follows(following_id);

COMMENT ON TABLE follows IS 'Relasi follow antar user';

-- ============================================================================
-- PORTFOLIO
-- ============================================================================

-- Portfolios
CREATE TABLE portfolios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    judul VARCHAR(200) NOT NULL,
    slug VARCHAR(250) NOT NULL,
    thumbnail_url TEXT,
    status portfolio_status NOT NULL DEFAULT 'draft',
    admin_review_note TEXT,
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    
    CONSTRAINT portfolios_slug_unique UNIQUE (user_id, slug)
);

CREATE INDEX idx_portfolios_user ON portfolios(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_portfolios_status ON portfolios(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_portfolios_published ON portfolios(published_at DESC) WHERE status = 'published' AND deleted_at IS NULL;
CREATE INDEX idx_portfolios_pending ON portfolios(created_at) WHERE status = 'pending_review' AND deleted_at IS NULL;
CREATE INDEX idx_portfolios_slug ON portfolios(slug) WHERE deleted_at IS NULL;

COMMENT ON TABLE portfolios IS 'Portofolio karya user';
COMMENT ON COLUMN portfolios.slug IS 'URL-friendly identifier, auto-generated dari judul';
COMMENT ON COLUMN portfolios.admin_review_note IS 'Catatan review dari admin (alasan reject, feedback, dll)';

-- Portfolio Tags (many-to-many)
CREATE TABLE portfolio_tags (
    portfolio_id UUID NOT NULL REFERENCES portfolios(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (portfolio_id, tag_id)
);

CREATE INDEX idx_portfolio_tags_tag ON portfolio_tags(tag_id);

COMMENT ON TABLE portfolio_tags IS 'Relasi many-to-many portfolio dan tags';

-- Content Blocks
CREATE TABLE content_blocks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    portfolio_id UUID NOT NULL REFERENCES portfolios(id) ON DELETE CASCADE,
    block_type content_block_type NOT NULL,
    block_order INTEGER NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT content_blocks_order_positive CHECK (block_order >= 0),
    CONSTRAINT content_blocks_unique_order UNIQUE (portfolio_id, block_order) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX idx_content_blocks_portfolio ON content_blocks(portfolio_id);
CREATE INDEX idx_content_blocks_order ON content_blocks(portfolio_id, block_order);

COMMENT ON TABLE content_blocks IS 'Modular content blocks untuk portofolio';
COMMENT ON COLUMN content_blocks.block_type IS 'Tipe block: text, image, table, youtube, button, embed';
COMMENT ON COLUMN content_blocks.payload IS 'Konten block dalam format JSON sesuai tipe';

-- Portfolio Likes
CREATE TABLE portfolio_likes (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    portfolio_id UUID NOT NULL REFERENCES portfolios(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (user_id, portfolio_id)
);

CREATE INDEX idx_portfolio_likes_portfolio ON portfolio_likes(portfolio_id);

COMMENT ON TABLE portfolio_likes IS 'Like/favorit portofolio oleh user';

-- ============================================================================
-- ADMIN CONFIGURATION
-- ============================================================================

-- App Settings (untuk konfigurasi seperti admin login path)
CREATE TABLE app_settings (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL
);

COMMENT ON TABLE app_settings IS 'Konfigurasi aplikasi (termasuk admin login path)';

-- ============================================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Function: Generate nama kelas
CREATE OR REPLACE FUNCTION generate_nama_kelas()
RETURNS TRIGGER AS $$
DECLARE
    v_kode_jurusan VARCHAR(10);
    v_tingkat_romawi VARCHAR(4);
BEGIN
    -- Get kode jurusan
    SELECT UPPER(kode) INTO v_kode_jurusan FROM jurusan WHERE id = NEW.jurusan_id;
    
    -- Convert tingkat to Roman numeral
    v_tingkat_romawi := CASE NEW.tingkat
        WHEN 10 THEN 'X'
        WHEN 11 THEN 'XI'
        WHEN 12 THEN 'XII'
    END;
    
    -- Generate nama: XII-RPL-A
    NEW.nama := v_tingkat_romawi || '-' || v_kode_jurusan || '-' || NEW.rombel;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_kelas_generate_nama
    BEFORE INSERT OR UPDATE ON kelas
    FOR EACH ROW
    EXECUTE FUNCTION generate_nama_kelas();

-- Function: Generate slug dari judul
CREATE OR REPLACE FUNCTION generate_portfolio_slug()
RETURNS TRIGGER AS $$
DECLARE
    v_base_slug VARCHAR(250);
    v_slug VARCHAR(250);
    v_counter INTEGER := 0;
BEGIN
    -- Generate base slug: lowercase, replace spaces with dash, remove special chars
    v_base_slug := LOWER(TRIM(NEW.judul));
    v_base_slug := REGEXP_REPLACE(v_base_slug, '[^a-z0-9\s-]', '', 'g');
    v_base_slug := REGEXP_REPLACE(v_base_slug, '\s+', '-', 'g');
    v_base_slug := REGEXP_REPLACE(v_base_slug, '-+', '-', 'g');
    v_base_slug := TRIM(BOTH '-' FROM v_base_slug);
    v_base_slug := LEFT(v_base_slug, 200);
    
    v_slug := v_base_slug;
    
    -- Check uniqueness and append counter if needed
    WHILE EXISTS (
        SELECT 1 FROM portfolios 
        WHERE user_id = NEW.user_id 
        AND slug = v_slug 
        AND id != COALESCE(NEW.id, uuid_generate_v4())
        AND deleted_at IS NULL
    ) LOOP
        v_counter := v_counter + 1;
        v_slug := v_base_slug || '-' || v_counter;
    END LOOP;
    
    NEW.slug := v_slug;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_portfolio_generate_slug
    BEFORE INSERT OR UPDATE OF judul ON portfolios
    FOR EACH ROW
    EXECUTE FUNCTION generate_portfolio_slug();

-- Function: Set published_at when status changes to published
CREATE OR REPLACE FUNCTION set_portfolio_published_at()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'published' AND (OLD.status IS NULL OR OLD.status != 'published') THEN
        NEW.published_at := NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_portfolio_set_published_at
    BEFORE UPDATE ON portfolios
    FOR EACH ROW
    EXECUTE FUNCTION set_portfolio_published_at();

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to relevant tables
CREATE TRIGGER trg_jurusan_updated_at BEFORE UPDATE ON jurusan FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_tahun_ajaran_updated_at BEFORE UPDATE ON tahun_ajaran FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_kelas_updated_at BEFORE UPDATE ON kelas FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_tags_updated_at BEFORE UPDATE ON tags FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_user_social_links_updated_at BEFORE UPDATE ON user_social_links FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_portfolios_updated_at BEFORE UPDATE ON portfolios FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_content_blocks_updated_at BEFORE UPDATE ON content_blocks FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Function: Ensure only one active tahun_ajaran
CREATE OR REPLACE FUNCTION ensure_single_active_tahun_ajaran()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_active = TRUE THEN
        UPDATE tahun_ajaran SET is_active = FALSE 
        WHERE id != NEW.id AND is_active = TRUE AND deleted_at IS NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tahun_ajaran_single_active
    AFTER INSERT OR UPDATE OF is_active ON tahun_ajaran
    FOR EACH ROW
    WHEN (NEW.is_active = TRUE)
    EXECUTE FUNCTION ensure_single_active_tahun_ajaran();

-- Function: Sync kelas_id to student_class_history
CREATE OR REPLACE FUNCTION sync_student_class_history()
RETURNS TRIGGER AS $$
DECLARE
    v_tahun_ajaran_id UUID;
BEGIN
    IF NEW.kelas_id IS NOT NULL AND NEW.role IN ('student', 'alumni') THEN
        -- Get tahun_ajaran_id from kelas
        SELECT tahun_ajaran_id INTO v_tahun_ajaran_id FROM kelas WHERE id = NEW.kelas_id;
        
        -- Set all previous history to not current
        UPDATE student_class_history SET is_current = FALSE WHERE user_id = NEW.id;
        
        -- Insert or update history
        INSERT INTO student_class_history (user_id, kelas_id, tahun_ajaran_id, is_current)
        VALUES (NEW.id, NEW.kelas_id, v_tahun_ajaran_id, TRUE)
        ON CONFLICT (user_id, kelas_id, tahun_ajaran_id) 
        DO UPDATE SET is_current = TRUE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_sync_class_history
    AFTER INSERT OR UPDATE OF kelas_id ON users
    FOR EACH ROW
    EXECUTE FUNCTION sync_student_class_history();

-- ============================================================================
-- INITIAL DATA
-- ============================================================================

-- Insert default admin login path setting
INSERT INTO app_settings (key, value, description) VALUES
('admin_login_path', '"loginadmin"', 'Path untuk halaman login admin (tanpa slash)');

-- Insert sample tahun ajaran
INSERT INTO tahun_ajaran (tahun_mulai, is_active, promotion_month, promotion_day) VALUES
(2024, FALSE, 7, 1),
(2025, TRUE, 7, 1);

-- Insert sample jurusan
INSERT INTO jurusan (nama, kode) VALUES
('Rekayasa Perangkat Lunak', 'rpl'),
('Teknik Komputer dan Jaringan', 'tkj'),
('Multimedia', 'mm'),
('Desain Komunikasi Visual', 'dkv'),
('Animasi', 'ani');

-- Insert sample tags
INSERT INTO tags (nama) VALUES
('Web Development'),
('Mobile App'),
('UI/UX Design'),
('Graphic Design'),
('3D Modeling'),
('Animation'),
('Video Editing'),
('Photography'),
('Illustration'),
('Game Development');

-- ============================================================================
-- VIEWS (untuk kemudahan query)
-- ============================================================================

-- View: User profile dengan info kelas
CREATE OR REPLACE VIEW v_user_profiles AS
SELECT 
    u.id,
    u.username,
    u.email,
    u.nama,
    u.bio,
    u.avatar_url,
    u.banner_url,
    u.role,
    u.nisn,
    u.nis,
    u.tahun_masuk,
    u.tahun_lulus,
    u.is_active,
    u.created_at,
    k.id AS kelas_id,
    k.nama AS kelas_nama,
    k.tingkat AS kelas_tingkat,
    j.id AS jurusan_id,
    j.nama AS jurusan_nama,
    j.kode AS jurusan_kode,
    (SELECT COUNT(*) FROM follows WHERE following_id = u.id) AS follower_count,
    (SELECT COUNT(*) FROM follows WHERE follower_id = u.id) AS following_count,
    (SELECT COUNT(*) FROM portfolios WHERE user_id = u.id AND status = 'published' AND deleted_at IS NULL) AS portfolio_count
FROM users u
LEFT JOIN kelas k ON u.kelas_id = k.id AND k.deleted_at IS NULL
LEFT JOIN jurusan j ON k.jurusan_id = j.id AND j.deleted_at IS NULL
WHERE u.deleted_at IS NULL;

-- View: Published portfolios dengan info user
CREATE OR REPLACE VIEW v_published_portfolios AS
SELECT 
    p.id,
    p.user_id,
    p.judul,
    p.slug,
    p.thumbnail_url,
    p.published_at,
    p.created_at,
    p.updated_at,
    u.username AS user_username,
    u.nama AS user_nama,
    u.avatar_url AS user_avatar,
    u.role AS user_role,
    k.nama AS user_kelas,
    j.nama AS user_jurusan,
    (SELECT COUNT(*) FROM portfolio_likes WHERE portfolio_id = p.id) AS like_count,
    (SELECT ARRAY_AGG(t.nama) FROM portfolio_tags pt JOIN tags t ON pt.tag_id = t.id WHERE pt.portfolio_id = p.id) AS tags
FROM portfolios p
JOIN users u ON p.user_id = u.id AND u.deleted_at IS NULL
LEFT JOIN kelas k ON u.kelas_id = k.id
LEFT JOIN jurusan j ON k.jurusan_id = j.id
WHERE p.status = 'published' AND p.deleted_at IS NULL
ORDER BY p.published_at DESC;

-- ============================================================================
-- CLEANUP FUNCTIONS (untuk maintenance)
-- ============================================================================

-- Function: Cleanup expired refresh tokens
CREATE OR REPLACE FUNCTION cleanup_expired_tokens()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM refresh_tokens WHERE expires_at < NOW();
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    DELETE FROM token_blacklist WHERE expires_at < NOW();
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_expired_tokens() IS 'Hapus refresh tokens dan blacklist yang sudah expired. Jalankan via cron job.';

-- ============================================================================
-- PERMISSIONS (contoh untuk role-based access)
-- ============================================================================

-- Create application roles (uncomment jika diperlukan)
-- CREATE ROLE grafikarsa_app LOGIN PASSWORD 'secure_password';
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO grafikarsa_app;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO grafikarsa_app;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafikarsa_app;
