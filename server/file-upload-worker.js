export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Handle CORS preflight requests
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 200,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    // File upload endpoint
    if (request.method === 'POST' && url.pathname === '/upload') {
      return handleFileUpload(request, env);
    }

    // Get file download URL endpoint
    if (request.method === 'GET' && url.pathname.startsWith('/file/')) {
      const fileName = url.pathname.split('/file/')[1];
      return getDownloadUrl(fileName, env);
    }

    return new Response('Not found', { status: 404 });
  },
};

async function handleFileUpload(request, env) {
  try {
    const formData = await request.formData();
    const file = formData.get('file');

    if (!file) {
      return new Response(JSON.stringify({ error: 'No file provided' }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    // Generate unique filename
    const timestamp = Date.now();
    const randomString = Math.random().toString(36).substring(2, 15);
    const fileExtension = file.name.split('.').pop();
    const fileName = `${timestamp}-${randomString}.${fileExtension}`;

    // Upload to Supabase Storage
    const uploadResponse = await fetch(
      `${env.SUPABASE_URL}/storage/v1/object/files/${fileName}`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.SUPABASE_ANON_KEY}`,
          'Content-Type': file.type,
        },
        body: file.stream(),
      }
    );

    if (!uploadResponse.ok) {
      const error = await uploadResponse.text();
      return new Response(JSON.stringify({ error: 'Upload failed', details: error }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    const uploadResult = await uploadResponse.json();

    // Return success response with file info
    return new Response(JSON.stringify({
      success: true,
      fileName: fileName,
      downloadUrl: `${env.PUBLIC_BASE_URL}/file/${fileName}`,
      supabaseUrl: `${env.SUPABASE_URL}/storage/v1/object/public/files/${fileName}`,
      originalName: file.name,
      size: file.size,
      type: file.type
    }), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: 'Upload failed', details: error.message }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });
  }
}

async function getDownloadUrl(fileName, env) {
  try {
    // Get file info from Supabase
    const fileResponse = await fetch(
      `${env.SUPABASE_URL}/storage/v1/object/info/public/files/${fileName}`,
      {
        headers: {
          'Authorization': `Bearer ${env.SUPABASE_ANON_KEY}`,
        },
      }
    );

    if (!fileResponse.ok) {
      return new Response(JSON.stringify({ error: 'File not found' }), {
        status: 404,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    const fileInfo = await fileResponse.json();

    // Return download URL
    return new Response(JSON.stringify({
      fileName: fileName,
      downloadUrl: `${env.SUPABASE_URL}/storage/v1/object/public/files/${fileName}`,
      fileInfo: fileInfo
    }), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: 'Failed to get file info', details: error.message }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });
  }
}