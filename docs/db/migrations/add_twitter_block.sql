-- Migration: Add twitter to content_block_type ENUM
-- Run this on the production PostgreSQL database

ALTER TYPE content_block_type ADD VALUE IF NOT EXISTS 'twitter';

-- Verify the ENUM values
SELECT enum_range(NULL::content_block_type);
