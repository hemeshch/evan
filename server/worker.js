// DataBroadcaster Durable Object
//
// Notes on hardening:
//  - WebSocket upgrade is scoped to "/" or "/ws" (POST /broadcast carrying
//    an Upgrade header is NOT treated as a WS request).
//  - Sockets identify their role via ?role=agent|user_device on connect.
//    Broadcasts are routed by `recipient` instead of fan-out-to-everyone,
//    so the agent does not receive its own echoes.
//  - Uses hibernatable WebSockets via state.acceptWebSocket so the DO can
//    be evicted without dropping live connections or losing state.
//  - latestData is persisted in DO storage instead of an in-memory field.
//  - POST /broadcast requires Authorization: Bearer <BROADCAST_TOKEN>
//    when the secret is configured (recommended for any public deploy).

const VALID_ROLES = new Set(['agent', 'user_device']);

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

export class DataBroadcaster {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);

    // WebSocket upgrade — path-scoped so POST /broadcast with an Upgrade
    // header cannot be mis-routed as a websocket connection.
    if (
      request.headers.get('Upgrade') === 'websocket' &&
      (url.pathname === '/' || url.pathname === '/ws')
    ) {
      return this.handleWebSocket(request, url);
    }

    if (request.method === 'POST' && url.pathname === '/broadcast') {
      return this.handleBroadcast(request);
    }

    if (request.method === 'GET' && url.pathname === '/latest') {
      const latest = await this.state.storage.get('latestData');
      return jsonResponse(latest || { error: 'No data available' });
    }

    return new Response('Not found', { status: 404 });
  }

  async handleWebSocket(request, url) {
    const role = (url.searchParams.get('role') || '').toLowerCase();
    if (!VALID_ROLES.has(role)) {
      return new Response(
        'Missing or invalid ?role= (must be "agent" or "user_device")',
        { status: 400 }
      );
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    // Hibernatable accept — runtime delivers messages to this DO's
    // webSocketMessage/Close/Error handlers even after eviction.
    this.state.acceptWebSocket(server, [role]);
    server.serializeAttachment({ role });

    return new Response(null, { status: 101, webSocket: client });
  }

  // Inbound WS frames are not used today (clients push via /broadcast HTTP),
  // but the handler is required for the hibernation API.
  async webSocketMessage(ws, _message) {
    // Intentionally ignored.
  }

  async webSocketClose(ws, code, reason, _wasClean) {
    try {
      ws.close(code, reason);
    } catch {
      // already closed
    }
  }

  async webSocketError(ws, error) {
    console.error('websocket error', error);
    try {
      ws.close(1011, 'error');
    } catch {
      // already closed
    }
  }

  async handleBroadcast(request) {
    // Require a shared-secret token when configured. Without auth, any
    // internet client could inject new_prompt messages and drive the agent.
    if (this.env.BROADCAST_TOKEN) {
      const auth = request.headers.get('Authorization') || '';
      if (auth !== `Bearer ${this.env.BROADCAST_TOKEN}`) {
        return jsonResponse({ error: 'Unauthorized' }, { status: 401 });
      }
    }

    let jsonData;
    try {
      jsonData = await request.json();
    } catch {
      return jsonResponse({ error: 'Invalid JSON data' }, { status: 400 });
    }

    // Persist the latest data so it survives DO eviction.
    await this.state.storage.put('latestData', jsonData);

    const recipient = (jsonData.recipient || 'all').toString();
    const message = JSON.stringify(jsonData);

    let delivered = 0;
    let dropped = 0;
    const sockets = this.state.getWebSockets();
    for (const ws of sockets) {
      const attachment = (ws.deserializeAttachment && ws.deserializeAttachment()) || {};
      const role = attachment.role;

      // Routing: "all" goes everywhere; otherwise the recipient must match
      // the socket's declared role. This prevents the agent from receiving
      // user_device-targeted echoes (and vice versa).
      const shouldDeliver = recipient === 'all' || recipient === role;
      if (!shouldDeliver) continue;

      try {
        ws.send(message);
        delivered++;
      } catch (e) {
        console.error('ws.send failed', e);
        try {
          ws.close(1011, 'send failed');
        } catch {
          // already closed
        }
        dropped++;
      }
    }

    return jsonResponse({
      success: true,
      message: 'Data broadcasted successfully',
      delivered,
      dropped,
    });
  }
}

export default {
  async fetch(request, env, _ctx) {
    // Handle CORS preflight requests
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

    // Route to the single Durable Object instance.
    const id = env.DATA_BROADCASTER.idFromName('broadcaster');
    const stub = env.DATA_BROADCASTER.get(id);
    return stub.fetch(request);
  },
};
