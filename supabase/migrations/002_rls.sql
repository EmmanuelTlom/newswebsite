-- National Detective Magazine — Row Level Security Policies
-- Run AFTER 001_schema.sql

-- Helper: returns true if the calling user is a registered admin
CREATE OR REPLACE FUNCTION public.is_ndm_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = auth.uid() AND is_admin = true
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Enable RLS on all tables
ALTER TABLE public.categories          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.articles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_messages    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advertise_inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_settings       ENABLE ROW LEVEL SECURITY;

-- ── CATEGORIES ────────────────────────────────────────────────────────────────
-- Anyone can read categories; only admins can write them.
CREATE POLICY "categories_read_public"  ON public.categories FOR SELECT USING (true);
CREATE POLICY "categories_write_admin"  ON public.categories FOR ALL    USING (is_ndm_admin()) WITH CHECK (is_ndm_admin());

-- ── ARTICLES ──────────────────────────────────────────────────────────────────
-- Public can read published articles; admins can read/write all.
CREATE POLICY "articles_read_published" ON public.articles FOR SELECT
  USING (published = true OR is_ndm_admin());
CREATE POLICY "articles_write_admin"    ON public.articles FOR ALL
  USING (is_ndm_admin()) WITH CHECK (is_ndm_admin());

-- ── ADMIN_USERS ───────────────────────────────────────────────────────────────
-- Only admins can read/write admin_users
CREATE POLICY "admin_users_admin_only"  ON public.admin_users FOR ALL
  USING (is_ndm_admin()) WITH CHECK (is_ndm_admin());

-- ── CONTACT_MESSAGES ─────────────────────────────────────────────────────────
-- Anyone (anon) can INSERT; only admins can SELECT/UPDATE/DELETE
CREATE POLICY "contact_insert_public"   ON public.contact_messages FOR INSERT WITH CHECK (true);
CREATE POLICY "contact_read_admin"      ON public.contact_messages FOR SELECT USING (is_ndm_admin());
CREATE POLICY "contact_update_admin"    ON public.contact_messages FOR UPDATE USING (is_ndm_admin());
CREATE POLICY "contact_delete_admin"    ON public.contact_messages FOR DELETE USING (is_ndm_admin());

-- ── ADVERTISE_INQUIRIES ───────────────────────────────────────────────────────
CREATE POLICY "adv_insert_public"       ON public.advertise_inquiries FOR INSERT WITH CHECK (true);
CREATE POLICY "adv_read_admin"          ON public.advertise_inquiries FOR SELECT USING (is_ndm_admin());
CREATE POLICY "adv_update_admin"        ON public.advertise_inquiries FOR UPDATE USING (is_ndm_admin());
CREATE POLICY "adv_delete_admin"        ON public.advertise_inquiries FOR DELETE USING (is_ndm_admin());

-- ── SITE_SETTINGS ─────────────────────────────────────────────────────────────
-- Public can read; only admins can update
CREATE POLICY "settings_read_public"    ON public.site_settings FOR SELECT USING (true);
CREATE POLICY "settings_write_admin"    ON public.site_settings FOR ALL    USING (is_ndm_admin()) WITH CHECK (is_ndm_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- STORAGE BUCKETS
-- Run in Supabase Dashboard → Storage → New bucket:
--   Name: "photos"   → Public bucket: YES  → Save
-- Then in Storage → Policies add:
--   "photos_upload_admin" on bucket "photos": INSERT allowed when is_ndm_admin()
-- Or run the SQL below if storage policies are supported via SQL editor in your plan:

-- INSERT INTO storage.buckets (id, name, public) VALUES ('photos', 'photos', true)
--   ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- BOOTSTRAP YOUR FIRST ADMIN
-- After signing up via Supabase Auth with your email, run:
--   INSERT INTO public.admin_users (user_id, email, name, is_admin)
--   VALUES (auth.uid(), 'your@email.com', 'Your Name', true);
-- Or from the SQL editor (replace with your actual user_id from auth.users):
--   INSERT INTO public.admin_users (user_id, email, name, is_admin)
--   SELECT id, email, email, true FROM auth.users WHERE email = 'your@email.com';
