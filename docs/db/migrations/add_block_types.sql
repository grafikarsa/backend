-- Migration: Add new content_block_type ENUM values
-- Run this on the production PostgreSQL database

-- Add new block types to the content_block_type ENUM
ALTER TYPE content_block_type ADD VALUE IF NOT EXISTS 'figma';
ALTER TYPE content_block_type ADD VALUE IF NOT EXISTS 'canva';
ALTER TYPE content_block_type ADD VALUE IF NOT EXISTS 'ppt';
ALTER TYPE content_block_type ADD VALUE IF NOT EXISTS 'pdf';
ALTER TYPE content_block_type ADD VALUE IF NOT EXISTS 'doc';
ALTER TYPE content_block_type ADD VALUE IF NOT EXISTS 'website';

-- Verify the ENUM values
SELECT enum_range(NULL::content_block_type);
