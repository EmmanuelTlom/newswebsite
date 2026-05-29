// National Detective Magazine — Supabase-backed data layer
// Exposes window.NDMData with async methods for all data access.
// Requires: @supabase/supabase-js loaded globally, and window.NDM_CONFIG set.

(function (global) {
  'use strict';

  const cfg = global.NDM_CONFIG;
  if (!cfg || !cfg.url || !cfg.key) {
    console.error('[NDMData] NDM_CONFIG missing. Include assets/ndm-config.js first.');
    return;
  }
  if (!global.supabase || !global.supabase.createClient) {
    console.error('[NDMData] supabase-js not loaded. Include it before ndm-data.js.');
    return;
  }

  // Disable autoRefreshToken to prevent silent SDK hangs (same pattern as ama-data.js).
  // We call ensureFreshSession() before writes instead.
  const sb = global.supabase.createClient(cfg.url, cfg.key, {
    auth: {
      persistSession: true,
      autoRefreshToken: false,
      detectSessionInUrl: true,
      lock: (_name, _acquireTimeout, fn) => fn(),
    }
  });

  global.NDMData_VERSION = '1';

  function withTimeout(promise, ms, label) {
    return Promise.race([
      promise,
      new Promise((_, reject) => setTimeout(() => reject(new Error(label || 'timeout')), ms))
    ]);
  }

  let _refreshInFlight = null;
  function _readStoredSession() {
    try {
      const projectRef = (cfg.url.match(/https:\/\/([a-z0-9]+)/i) || [])[1] || '';
      const key = 'sb-' + projectRef + '-auth-token';
      const raw = localStorage.getItem(key);
      if (!raw) return null;
      return JSON.parse(raw);
    } catch (_) { return null; }
  }
  async function ensureFreshSession() {
    const stored = _readStoredSession();
    if (!stored) throw new Error('Not signed in. Please sign in again.');
    const expiresAt = (stored.expires_at || 0) * 1000;
    if (expiresAt - Date.now() > 5 * 60 * 1000) return;
    if (!_refreshInFlight) {
      _refreshInFlight = withTimeout(sb.auth.refreshSession(), 5000, 'refresh-timeout')
        .finally(() => { _refreshInFlight = null; });
    }
    try {
      const { error } = await _refreshInFlight;
      if (error) throw error;
    } catch (e) {
      throw new Error('Session expired. Sign out and back in.');
    }
  }

  // Sanitise paste input from Word/iOS
  function sanitizeString(s) {
    if (typeof s !== 'string') return s;
    return s
      .replace(/[​-‍﻿]/g, '')
      .replace(/[''‚‛]/g, "'")
      .replace(/[""„‟]/g, '"')
      .replace(/[–—]/g, '-')
      .replace(/…/g, '...')
      .replace(/ /g, ' ')
      .replace(/\r\n?/g, '\n')
      .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
  }
  function sanitizePayload(obj) {
    if (!obj || typeof obj !== 'object') return obj;
    const out = Array.isArray(obj) ? [] : {};
    for (const k of Object.keys(obj)) {
      const v = obj[k];
      if (typeof v === 'string') out[k] = sanitizeString(v);
      else if (Array.isArray(v)) out[k] = v.map(x => typeof x === 'string' ? sanitizeString(x) : x);
      else out[k] = v;
    }
    return out;
  }

  function todayISO() {
    const d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }

  // ── PUBLIC READS ────────────────────────────────────────────────────────────

  async function getPublishedArticles({ limit = 20, offset = 0, categorySlug = null } = {}) {
    let q = sb.from('articles')
      .select('id,title,slug,excerpt,cover_image,category_name,category_color,author_name,featured,published_at,views')
      .eq('published', true)
      .order('published_at', { ascending: false })
      .range(offset, offset + limit - 1);
    if (categorySlug) {
      const cat = await getCategoryBySlug(categorySlug);
      if (cat) q = q.eq('category_id', cat.id);
    }
    const { data, error } = await q;
    if (error) { console.error(error); return []; }
    return data || [];
  }

  async function getFeaturedArticles(limit = 4) {
    const { data, error } = await sb.from('articles')
      .select('id,title,slug,excerpt,cover_image,category_name,category_color,author_name,published_at')
      .eq('published', true).eq('featured', true)
      .order('published_at', { ascending: false }).limit(limit);
    if (error) { console.error(error); return []; }
    return data || [];
  }

  async function getArticleBySlug(slug) {
    const { data, error } = await sb.from('articles')
      .select('*').eq('slug', slug).eq('published', true).maybeSingle();
    if (error) { console.error(error); return null; }
    return data;
  }

  async function getCategories() {
    const { data, error } = await sb.from('categories')
      .select('*').order('sort_order').order('name');
    if (error) { console.error(error); return []; }
    return data || [];
  }

  async function getCategoryBySlug(slug) {
    const { data } = await sb.from('categories').select('*').eq('slug', slug).maybeSingle();
    return data;
  }

  async function getSiteSettings() {
    const fallback = {
      tagline: 'Uncovering the Truth, Every Day',
      about_text: 'National Detective Magazine — Nigeria\'s foremost investigative publication.',
      contact_email: 'info@nationaldetective.ng',
      contact_phone: '', contact_address: '',
      whatsapp: '', facebook: '', twitter: '', instagram: ''
    };
    const { data, error } = await sb.from('site_settings').select('*').eq('id', 1).maybeSingle();
    if (error) { console.error(error); return fallback; }
    return data || fallback;
  }

  async function incrementViews(articleId) {
    await sb.rpc('increment_article_views', { p_article_id: articleId }).catch(() => {});
  }

  // Public form submissions — no auth required
  async function submitContactMessage(payload) {
    const { error } = await withTimeout(
      sb.from('contact_messages').insert(sanitizePayload(payload)),
      10000, 'contact-insert-timeout'
    );
    if (error) throw error;
    return true;
  }

  async function submitAdvertiseInquiry(payload) {
    const { error } = await withTimeout(
      sb.from('advertise_inquiries').insert(sanitizePayload(payload)),
      10000, 'advertise-insert-timeout'
    );
    if (error) throw error;
    return true;
  }

  // ── ADMIN READS ─────────────────────────────────────────────────────────────

  async function getAllArticles() {
    const { data, error } = await sb.from('articles')
      .select('id,title,slug,category_name,category_color,featured,published,published_at,created_at,views')
      .order('created_at', { ascending: false });
    if (error) { console.error(error); return []; }
    return data || [];
  }

  async function getArticleForEdit(id) {
    const { data, error } = await sb.from('articles').select('*').eq('id', id).maybeSingle();
    if (error) throw error;
    return data;
  }

  async function getContactMessages() {
    const { data, error } = await sb.from('contact_messages')
      .select('*').order('created_at', { ascending: false });
    if (error) { console.error(error); return []; }
    return data || [];
  }

  async function getAdvertiseInquiries() {
    const { data, error } = await sb.from('advertise_inquiries')
      .select('*').order('created_at', { ascending: false });
    if (error) { console.error(error); return []; }
    return data || [];
  }

  // ── GENERIC CRUD ────────────────────────────────────────────────────────────

  const TABLE_MAP = {
    articles:   'articles',
    categories: 'categories',
    messages:   'contact_messages',
    inquiries:  'advertise_inquiries',
  };

  async function createItem(type, item) {
    const table = TABLE_MAP[type];
    if (!table) throw new Error('Unknown type: ' + type);
    const { data, error } = await withTimeout(
      sb.from(table).insert(sanitizePayload(item)).select().single(),
      25000, 'insert-timeout'   // 25s — articles with long content need time on slow connections
    );
    if (error) throw error;
    return data;
  }

  async function updateItem(type, id, item) {
    const table = TABLE_MAP[type];
    if (!table) throw new Error('Unknown type: ' + type);
    const { data, error } = await withTimeout(
      sb.from(table).update(sanitizePayload(item)).eq('id', id).select().single(),
      25000, 'update-timeout'
    );
    if (error) throw error;
    return data;
  }

  async function deleteItem(type, id) {
    const table = TABLE_MAP[type];
    if (!table) throw new Error('Unknown type: ' + type);
    const { error } = await withTimeout(
      sb.from(table).delete().eq('id', id),
      15000, 'delete-timeout'
    );
    if (error) throw error;
  }

  async function saveSettings(patch) {
    const { error } = await withTimeout(
      sb.from('site_settings').update(sanitizePayload(patch)).eq('id', 1),
      15000, 'settings-timeout'
    );
    if (error) throw error;
    return true;
  }

  // ── AUTH ────────────────────────────────────────────────────────────────────

  async function signInWithPassword(email, password) {
    return sb.auth.signInWithPassword({ email, password });
  }
  async function signOut() {
    return sb.auth.signOut();
  }
  async function getSession() {
    const { data } = await sb.auth.getSession();
    return data.session;
  }
  async function getCurrentAdmin() {
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return null;
    const { data: admin } = await sb.from('admin_users')
      .select('*').eq('user_id', user.id).maybeSingle();
    return { user, admin };
  }
  function onAuthStateChange(cb) {
    return sb.auth.onAuthStateChange(cb);
  }

  // ── STORAGE ─────────────────────────────────────────────────────────────────

  async function uploadPhoto(file) {
    // Refresh session first — if this fails it means the user isn't logged in properly
    try {
      await ensureFreshSession();
    } catch (sessionErr) {
      throw new Error('Session expired. Please sign out and sign back in, then try again.');
    }

    const safeName = file.name.replace(/[^\w.\-]+/g, '_');
    const path = 'articles/' + Date.now() + '-' + safeName;

    const { data, error } = await withTimeout(
      sb.storage.from('photos').upload(path, file, {
        contentType: file.type,
        upsert: false,
      }),
      120000, 'photo-upload-timeout'  // 120s for large images on slow connections
    );

    if (error) {
      // Translate common Supabase storage errors into plain English
      const msg = (error.message || error.error || '').toLowerCase();
      if (msg.includes('bucket') || msg.includes('not found')) {
        throw new Error(
          'The "photos" storage bucket is missing. ' +
          'Fix: Go to your Supabase dashboard → Storage → Create a new bucket named exactly "photos" and tick "Public bucket". ' +
          'Then run supabase/migrations/003_video.sql in the SQL editor.'
        );
      }
      if (msg.includes('policy') || msg.includes('violates') || msg.includes('403') || msg.includes('unauthorized')) {
        throw new Error(
          'Upload blocked by Supabase. Your account may not be set as admin. ' +
          'Run this in the Supabase SQL editor: UPDATE public.admin_users SET is_admin = true WHERE email = \'your@email.com\'; ' +
          'Then sign out and back in.'
        );
      }
      if (msg.includes('duplicate') || msg.includes('already exists')) {
        // Retry with a slightly different name
        const retryPath = 'articles/' + Date.now() + '-retry-' + safeName;
        const { data: d2, error: e2 } = await sb.storage.from('photos').upload(retryPath, file, { contentType: file.type });
        if (e2) throw e2;
        const { data: pub2 } = sb.storage.from('photos').getPublicUrl(d2.path);
        return pub2.publicUrl;
      }
      throw error;
    }

    const { data: pub } = sb.storage.from('photos').getPublicUrl(data.path);
    return pub.publicUrl;
  }

  // ── EXPOSE ──────────────────────────────────────────────────────────────────

  global.NDMData = {
    supabase: sb,
    todayISO,
    // public reads
    getPublishedArticles, getFeaturedArticles, getArticleBySlug,
    getCategories, getCategoryBySlug, getSiteSettings, incrementViews,
    submitContactMessage, submitAdvertiseInquiry,
    // admin reads
    getAllArticles, getArticleForEdit,
    getContactMessages, getAdvertiseInquiries,
    // crud
    createItem, updateItem, deleteItem, saveSettings,
    // auth
    signInWithPassword, signOut, getSession, getCurrentAdmin, onAuthStateChange,
    // storage
    uploadPhoto,
  };

})(window);
