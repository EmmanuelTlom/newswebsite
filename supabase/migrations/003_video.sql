-- National Detective Magazine — Video support
-- Run this in Supabase SQL Editor after 001_schema.sql and 002_rls.sql

-- Add video_url column to articles (stores a YouTube or Vimeo URL)
ALTER TABLE public.articles
  ADD COLUMN IF NOT EXISTS video_url TEXT;

-- ─────────────────────────────────────────────────────────────────────────────
-- STORAGE BUCKET — run this if you haven't created it manually yet
-- ─────────────────────────────────────────────────────────────────────────────
-- If the "photos" bucket doesn't exist, create it:
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'photos', 'photos', true,
  10485760,   -- 10 MB limit per file
  ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Allow anyone to READ from the photos bucket (public)
CREATE POLICY "photos_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'photos');

-- Allow authenticated admins to UPLOAD to photos bucket
CREATE POLICY "photos_admin_upload"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'photos'
    AND EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE user_id = auth.uid() AND is_admin = true
    )
  );

-- Allow admins to DELETE their uploaded photos
CREATE POLICY "photos_admin_delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'photos'
    AND EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE user_id = auth.uid() AND is_admin = true
    )
  );
