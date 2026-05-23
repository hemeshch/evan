// DataBroadcaster Durable Object
// Note: WebSocket connections do NOT automatically receive latest data on connect
// Clients should use GET /latest endpoint if they need the current state
export class DataBroadcaster {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.sessions = [];
    this.latestData = null;
  }

  async fetch(request) {
    const url = new URL(request.url);

    // WebSocket upgrade endpoint
    if (request.headers.get('Upgrade') === 'websocket') {
      return this.handleWebSocket(request);
    }

    // POST endpoint to send data to all connected clients
    if (request.method === 'POST' && url.pathname === '/broadcast') {
      return this.handleBroadcast(request);
    }

    // GET endpoint to retrieve latest data
    if (request.method === 'GET' && url.pathname === '/latest') {
      return new Response(JSON.stringify(this.latestData || { error: 'No data available' }), {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    return new Response('Not found', { status: 404 });
  }

  async handleWebSocket(request) {
    const webSocketPair = new WebSocketPair();
    const [client, server] = Object.values(webSocketPair);

    server.accept();
    this.sessions.push(server);

    // WebSocket connection established - client is now ready to receive broadcasts
    // Note: Latest data is NOT automatically sent on connect

    server.addEventListener('close', () => {
      this.sessions = this.sessions.filter(session => session !== server);
    });

    server.addEventListener('error', () => {
      this.sessions = this.sessions.filter(session => session !== server);
    });

    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }

  async handleBroadcast(request) {
    try {
      const jsonData = await request.json();

      // Store the latest data
      this.latestData = jsonData;

      // Broadcast to all connected WebSocket clients
      const message = JSON.stringify(jsonData);
      this.sessions = this.sessions.filter(session => {
        try {
          session.send(message);
          return true;
        } catch {
          return false; // Remove disconnected sessions
        }
      });

      return new Response(JSON.stringify({
        success: true,
        message: 'Data broadcasted successfully',
        connectedClients: this.sessions.length
      }), {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    } catch (error) {
      return new Response(JSON.stringify({ error: 'Invalid JSON data' }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }
  }
}

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

    // Route to Durable Object
    const id = env.DATA_BROADCASTER.idFromName('broadcaster');
    const stub = env.DATA_BROADCASTER.get(id);
    return stub.fetch(request);
  },
};