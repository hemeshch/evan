# Evan Server

A high-performance real-time data broadcasting and file storage service built on Cloudflare Workers infrastructure.

## 🚀 Features

- **Real-time WebSocket Broadcasting** - Instantly push data to all connected clients
- **File Upload & Storage** - Secure file handling with Supabase integration
- **Zero Configuration** - Deploy and run with minimal setup
- **Global Edge Network** - Powered by Cloudflare's worldwide infrastructure
- **CORS Enabled** - Seamless cross-origin integration

## 🏗️ Architecture

The system consists of two independent Cloudflare Workers:

### Data Transmitter
- WebSocket connections for real-time communication
- Broadcast messaging to all connected clients
- Latest data retrieval endpoint
- Durable Objects for stateful WebSocket management

### File Upload API
- Multipart form data file uploads
- Automatic file naming with collision prevention
- Direct integration with Supabase Storage
- File metadata retrieval

## 📦 Services

| Service | Endpoint | Description |
|---------|----------|-------------|
| **WebSocket** | `wss://YOUR_DATA_TRANSMITTER.workers.dev` | Real-time data streaming |
| **Broadcast API** | `POST /broadcast` | Send data to all connected clients |
| **Latest Data** | `GET /latest` | Retrieve most recent broadcast |
| **File Upload** | `POST /upload` | Upload files to cloud storage |
| **File Info** | `GET /file/{fileName}` | Get file metadata and URLs |

## 🔧 Quick Start

### WebSocket Connection

```javascript
const ws = new WebSocket('wss://YOUR_DATA_TRANSMITTER.workers.dev');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Received:', data);
};
```

### Broadcasting Data

```javascript
fetch('https://YOUR_DATA_TRANSMITTER.workers.dev/broadcast', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    device: 'web',
    format: 'notification',
    content: 'Hello World'
  })
});
```

### File Upload

```javascript
const formData = new FormData();
formData.append('file', fileInput.files[0]);

fetch('https://YOUR_FILE_UPLOAD_API.workers.dev/upload', {
  method: 'POST',
  body: formData
});
```

## 🛠️ Development

### Prerequisites

- [Wrangler CLI](https://developers.cloudflare.com/workers/cli-wrangler/install-update/)
- Cloudflare account
- Supabase project (for file uploads)

### Local Development

1. From the repo root, enter this directory
```bash
cd server
```

2. Configure Wrangler
```bash
wrangler login
```

3. Run Data Transmitter locally
```bash
wrangler dev --config wrangler.toml
```

4. Run File Upload API locally
```bash
wrangler dev --config file-upload-wrangler.toml
```

### Deployment

Deploy Data Transmitter:
```bash
wrangler deploy --config wrangler.toml
```

Deploy File Upload API:
```bash
wrangler deploy --config file-upload-wrangler.toml
```

## 📊 API Reference

### Broadcast Message Structure

```json
{
  "device": "string",      // Required: Device identifier
  "format": "string",      // Required: Message format type
  "content": "string",     // Required: Message payload
  "timestamp": 1234567890, // Optional: Unix timestamp (ms)
  "...": "any"            // Additional custom fields allowed
}
```

### Upload Response

```json
{
  "success": true,
  "fileName": "1758346198562-abc123.pdf",
  "downloadUrl": "https://file-upload-api.../file/...",
  "supabaseUrl": "https://supabase.co/.../files/...",
  "originalName": "document.pdf",
  "size": 245678,
  "type": "application/pdf"
}
```

## 🧪 Testing

### HTML Test Pages

- `websocket-test.html` - Interactive WebSocket testing interface
- `upload-test.html` - File upload testing interface

### Test Files

- `upload-icon.js` - Programmatic file upload testing
- `upload-icon-simple.js` - Simplified upload testing

### Manual Testing

Open test HTML files directly in browser:
```bash
open websocket-test.html
open upload-test.html
```

## 📈 Performance & Limits

| Metric | Limit | Notes |
|--------|-------|-------|
| Max WebSocket Connections | Memory bound | Per Durable Object instance |
| Max File Size | ~100MB | Cloudflare request limit |
| Message Size | ~1MB | Practical limit for broadcasts |
| Response Time | <50ms | Global edge network |

## 🔒 Security Considerations

⚠️ **Current Implementation:**
- No authentication on endpoints
- Public file access via URLs
- Open WebSocket connections

**Recommended for Production:**
- Implement API key authentication
- Add JWT token validation
- Enable rate limiting
- Restrict CORS origins
- Add file access controls

## 🌍 CORS Configuration

All endpoints support CORS with:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, OPTIONS`
- `Access-Control-Allow-Headers: Content-Type`

## 📝 Configuration Files

### wrangler.toml
```toml
name = "data-transmitter"
main = "worker.js"
compatibility_date = "2024-01-01"

[[durable_objects.bindings]]
name = "DATA_BROADCASTER"
class_name = "DataBroadcaster"
```

### file-upload-wrangler.toml
```toml
name = "file-upload-api"
main = "file-upload-worker.js"
compatibility_date = "2024-01-01"

[vars]
SUPABASE_URL = "your-supabase-url"
SUPABASE_ANON_KEY = "your-anon-key"
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## 📄 License

This project is open source and available under the MIT License.

## 🔗 Links

- [Cloudflare Workers Documentation](https://developers.cloudflare.com/workers/)
- [Supabase Documentation](https://supabase.com/docs)
- [WebSocket API Reference](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API)

## 📞 Support

For issues and questions:
- Open an issue on GitHub
- Check the [SERVER-SPEC.md](./SERVER-SPEC.md) for detailed API documentation

---

Built with ⚡ by Hemesh Chadalavada