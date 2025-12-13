-- ============================================================================
-- Migration: Add Feedback Table
-- Description: Tabel untuk menyimpan feedback dari user (bug, saran, dll)
-- ============================================================================

-- Enum types untuk feedback
CREATE TYPE feedback_kategori AS ENUM ('bug', 'saran', 'lainnya');
CREATE TYPE feedback_status AS ENUM ('pending', 'read', 'resolved');

-- Feedback table
CREATE TABLE feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    kategori feedback_kategori NOT NULL,
    pesan TEXT NOT NULL,
    status feedback_status NOT NULL DEFAULT 'pending',
    admin_notes TEXT,
    resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_feedback_user ON feedback(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_feedback_status ON feedback(status);
CREATE INDEX idx_feedback_kategori ON feedback(kategori);
CREATE INDEX idx_feedback_created ON feedback(created_at DESC);

-- Comments
COMMENT ON TABLE feedback IS 'Feedback dari user (bug report, saran, dll)';
COMMENT ON COLUMN feedback.user_id IS 'NULL jika feedback dari guest (tidak login)';
COMMENT ON COLUMN feedback.admin_notes IS 'Catatan internal dari admin';

-- Trigger for updated_at
CREATE TRIGGER trg_feedback_updated_at BEFORE UPDATE ON feedback FOR EACH ROW EXECUTE FUNCTION update_updated_at();
