// File upload worker.
//
// Notes on hardening:
//  - Writes use SUPABASE_SERVICE_KEY (server-side role) so storage RLS
//    cannot also be triggered by anonymous clients hitting Supabase directly.
//    SUPABASE_ANON_KEY is still accepted as a fallback for backwards
//    compatibility but emits a console.warn.
//  - The uploaded Content-Type is whitelisted; anything else falls back to
//    application/octet-stream. This prevents stored-XSS via text/html
//    payloads served from this worker's domain.
//  - The object key is built from a strictly-validated file extension and
//    never echoes raw user-supplied filename segments, blocking path
//    injection into the bucket key.
//  - GET /file/<name> validates the name before contacting Supabase.
//  - Internal errors are logged with console.error but a generic message
//    is returned to the caller so Supabase request IDs / internals do not
//    leak to clients.

const ALLOWED_CONTENT_TYPES = new Set([
  'application/pdf',
  'application/zip',
  'application/json',
  'application/octet-stream',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'text/plain',
  'text/csv',
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'audio/mpeg',
  'audio/wav',
  'video/mp4',
]);

// Extensions are intentionally restrictive: 1-8 ASCII letters/digits.
const EXTENSION_RE = /^[A-Za-z0-9]{1,8}$/;
// Generated filenames use this exact pattern, so look-ups can reject
// anything that wasn't produced by this worker.
const STORED_NAME_RE = /^[0-9]{10,16}-[A-Za-z0-9]{6,32}\.[A-Za-z0-9]{1,8}$/;

function corsHeaders(extra = {}) {
  return {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    ...extra,
  };
}

function jsonResponse(body, init = {}) {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: corsHeaders(init.headers),
  });
}

function extractExtension(originalName) {
  if (!originalName || typeof originalName !== 'string') return 'bin';
  const idx = originalName.lastIndexOf('.');
  if (idx <= 0 || idx === originalName.length - 1) return 'bin';
  const ext = originalName.slice(idx + 1).toLowerCase();
  return EXTENSION_RE.test(ext) ? ext : 'bin';
}

function safeContentType(reportedType) {
  if (typeof reportedType === 'string' && ALLOWED_CONTENT_TYPES.has(reportedType.toLowerCase())) {
    return reportedType.toLowerCase();
  }
  return 'application/octet-stream';
}

function supabaseKey(env) {
  if (env.SUPABASE_SERVICE_KEY) return env.SUPABASE_SERVICE_KEY;
  if (env.SUPABASE_ANON_KEY) {
    console.warn(
      'file-upload-worker: SUPABASE_SERVICE_KEY not set; falling back to ' +
      'SUPABASE_ANON_KEY. Configure the service key for proper RLS bypass.'
    );
    return env.SUPABASE_ANON_KEY;
  }
  return null;
}

export default {
  async fetch(request, env, _ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 200,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      });
    }

    if (request.method === 'POST' && url.pathname === '/upload') {
      return handleFileUpload(request, env);
    }

    if (request.method === 'GET' && url.pathname.startsWith('/file/')) {
      const fileName = url.pathname.slice('/file/'.length);
      return getDownloadUrl(fileName, env);
    }

    return new Response('Not found', { status: 404 });
  },
};

async function handleFileUpload(request, env) {
  try {
    const key = supabaseKey(env);
    if (!key) {
      console.error('file-upload-worker: no Supabase key configured');
      return jsonResponse({ error: 'Upload service misconfigured' }, { status: 500 });
    }

    const formData = await request.formData();
    const file = formData.get('file');

    if (!file) {
      return jsonResponse({ error: 'No file provided' }, { status: 400 });
    }

    // Build a safe object key — never echo raw filename segments into the URL.
    const timestamp = Date.now();
    const randomString = Math.random().toString(36).substring(2, 15);
    const fileExtension = extractExtension(file.name);
    const fileName = `${timestamp}-${randomString}.${fileExtension}`;
    const contentType = safeContentType(file.type);

    const uploadResponse = await fetch(
      `${env.SUPABASE_URL}/storage/v1/object/files/${fileName}`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${key}`,
          'Content-Type': contentType,
        },
        body: file.stream(),
      }
    );

    if (!uploadResponse.ok) {
      const errorText = await uploadResponse.text().catch(() => '');
      console.error('Supabase upload failed', uploadResponse.status, errorText);
      return jsonResponse({ error: 'Upload failed' }, { status: 502 });
    }

    return jsonResponse({
      success: true,
      fileName,
      downloadUrl: `${env.PUBLIC_BASE_URL}/file/${fileName}`,
      supabaseUrl: `${env.SUPABASE_URL}/storage/v1/object/public/files/${fileName}`,
      originalName: typeof file.name === 'string' ? file.name : null,
      size: file.size,
      type: contentType,
    });
  } catch (error) {
    console.error('handleFileUpload error', error);
    return jsonResponse({ error: 'Upload failed' }, { status: 500 });
  }
}

async function getDownloadUrl(fileName, env) {
  try {
    if (!fileName || !STORED_NAME_RE.test(fileName)) {
      return jsonResponse({ error: 'File not found' }, { status: 404 });
    }

    const key = supabaseKey(env);
    if (!key) {
      console.error('file-upload-worker: no Supabase key configured');
      return jsonResponse({ error: 'Service misconfigured' }, { status: 500 });
    }

    const fileResponse = await fetch(
      `${env.SUPABASE_URL}/storage/v1/object/info/public/files/${fileName}`,
      {
        headers: {
          'Authorization': `Bearer ${key}`,
        },
      }
    );

    if (!fileResponse.ok) {
      // Treat any non-2xx (including 5xx) as "not available". The caller does
      // not need to distinguish between missing and upstream-error states.
      if (fileResponse.status >= 500) {
        console.error('Supabase file info upstream error', fileResponse.status);
      }
      return jsonResponse({ error: 'File not found' }, { status: 404 });
    }

    let fileInfo = null;
    try {
      fileInfo = await fileResponse.json();
    } catch (e) {
      console.error('Failed to parse Supabase file info', e);
      return jsonResponse({ error: 'File not found' }, { status: 404 });
    }

    return jsonResponse({
      fileName,
      downloadUrl: `${env.SUPABASE_URL}/storage/v1/object/public/files/${fileName}`,
      fileInfo,
    });
  } catch (error) {
    console.error('getDownloadUrl error', error);
    return jsonResponse({ error: 'Failed to get file info' }, { status: 500 });
  }
}
