-- National Detective Magazine — Database Schema
-- Run this in Supabase SQL editor (Dashboard → SQL Editor → New query)

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Categories
CREATE TABLE public.categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL UNIQUE,
  slug TEXT NOT NULL UNIQUE,
  color TEXT NOT NULL DEFAULT '#B91C1C',
  description TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Articles
CREATE TABLE public.articles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  excerpt TEXT,
  content TEXT,
  cover_image TEXT,
  category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
  category_name TEXT,          -- snapshot so articles survive category rename
  category_color TEXT,         -- snapshot
  author_name TEXT NOT NULL DEFAULT 'NDM Staff',
  author_image TEXT,
  featured BOOLEAN NOT NULL DEFAULT false,
  published BOOLEAN NOT NULL DEFAULT false,
  views INTEGER NOT NULL DEFAULT 0,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Admin users (mirrors auth.users via user_id)
CREATE TABLE public.admin_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  is_admin BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Contact form messages
CREATE TABLE public.contact_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  subject TEXT,
  message TEXT NOT NULL,
  read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Advertising inquiries
CREATE TABLE public.advertise_inquiries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  company TEXT,
  budget TEXT,
  ad_type TEXT,
  message TEXT,
  read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Site-wide settings (single row, id always = 1)
CREATE TABLE public.site_settings (
  id INTEGER PRIMARY KEY DEFAULT 1,
  tagline TEXT NOT NULL DEFAULT 'Uncovering the Truth, Every Day',
  about_text TEXT,
  contact_email TEXT DEFAULT 'info@nationaldetective.ng',
  contact_phone TEXT,
  contact_address TEXT,
  whatsapp TEXT,
  facebook TEXT,
  twitter TEXT,
  instagram TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed the single settings row
INSERT INTO public.site_settings (id, tagline, about_text)
VALUES (
  1,
  'Uncovering the Truth, Every Day',
  'National Detective Magazine is Nigeria''s foremost investigative news publication, delivering bold, fact-driven journalism since our founding. We hold power to account.'
) ON CONFLICT (id) DO NOTHING;

-- Seed default categories
INSERT INTO public.categories (name, slug, color, sort_order) VALUES
  ('Breaking News',    'breaking-news',    '#DC2626', 1),
  ('Investigations',   'investigations',   '#7C3AED', 2),
  ('Politics',         'politics',         '#1D4ED8', 3),
  ('Crime & Justice',  'crime-justice',    '#B45309', 4),
  ('Business',         'business',         '#065F46', 5),
  ('Entertainment',    'entertainment',    '#BE185D', 6),
  ('Sports',           'sports',           '#0369A1', 7),
  ('Opinion',          'opinion',          '#374151', 8)
ON CONFLICT (slug) DO NOTHING;

-- Indexes
CREATE INDEX idx_articles_published   ON public.articles(published, published_at DESC) WHERE published = true;
CREATE INDEX idx_articles_featured    ON public.articles(featured) WHERE featured = true AND published = true;
CREATE INDEX idx_articles_category    ON public.articles(category_id, published_at DESC);
CREATE INDEX idx_articles_slug        ON public.articles(slug);
CREATE INDEX idx_contact_unread       ON public.contact_messages(read, created_at DESC);
CREATE INDEX idx_inquiries_unread     ON public.advertise_inquiries(read, created_at DESC);

-- Auto-update updated_at on articles
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_articles_updated_at
  BEFORE UPDATE ON public.articles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_settings_updated_at
  BEFORE UPDATE ON public.site_settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Increment article views safely
CREATE OR REPLACE FUNCTION increment_article_views(p_article_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.articles SET views = views + 1 WHERE id = p_article_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
