# Evan Server API Specification

## Overview

The Evan Server consists of two Cloudflare Workers providing real-time data broadcasting and file storage capabilities.

| Service | URL | Purpose |
|---------|-----|---------|
| **Data Transmitter** | `YOUR_DATA_TRANSMITTER.workers.dev` | WebSocket & broadcast messaging |
| **File Upload API** | `YOUR_FILE_UPLOAD_API.workers.dev` | File storage via Supabase |

---

## 🔌 WebSocket Service

### Connection

**URL:** `wss://YOUR_DATA_TRANSMITTER.workers.dev`

**Protocol:** WebSocket

### Behavior

| Event | Description | Data Format |
|-------|-------------|-------------|
| **On Connect** | Connection established, ready to receive broadcasts | N/A |
| **On Message** | Receives all broadcast messages | JSON object |
| **On Disconnect** | Connection closed, removed from sessions | N/A |

### Message Flow

```
Client → [WebSocket Connect] → Server
                ↓
        [Ready to receive broadcasts]
                ↓
        [Listen for new broadcasts]
```

### Example WebSocket Message

```json
{
  "device": "mobile",
  "format": "notification",
  "content": "New update available",
  "timestamp": 1758346198562,
  "priority": "high"
}
```

---

## 📡 Broadcast API

### POST /broadcast

**URL:** `https://YOUR_DATA_TRANSMITTER.workers.dev/broadcast`

**Purpose:** Send data to all connected WebSocket clients

#### Request

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `device` | string | Yes | Device identifier (e.g., "mobile", "desktop", "iot") |
| `format` | string | Yes | Message format (e.g., "notification", "prompt", "sensor") |
| `content` | string | Yes | Message content |
| `timestamp` | number | No | Unix timestamp in milliseconds |
| `*` | any | No | Additional custom fields allowed |

**Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "device": "desktop",
  "format": "prompt",
  "content": "Please confirm your action",
  "timestamp": 1758346198562,
  "user": "test_user"
}
```

#### Response

**Success (200):**
```json
{
  "success": true,
  "message": "Data broadcasted successfully",
  "connectedClients": 5
}
```

**Error (400):**
```json
{
  "error": "Invalid JSON data"
}
```

---

## 📊 Latest Data API

### GET /latest

**URL:** `https://YOUR_DATA_TRANSMITTER.workers.dev/latest`

**Purpose:** Retrieve the most recent broadcast data

**Use Case:** Since WebSocket connections no longer auto-receive latest data on connect, use this endpoint to fetch the current state when needed

#### Response

**Success (200):**
```json
{
  "device": "mobile",
  "format": "notification",
  "content": "Last message",
  "timestamp": 1758346198562
}
```

**No Data (200):**
```json
{
  "error": "No data available"
}
```

---

## 📁 File Upload Service

### POST /upload

**URL:** `https://YOUR_FILE_UPLOAD_API.workers.dev/upload`

**Purpose:** Upload files to Supabase storage

#### Request

**Headers:**
```
Content-Type: multipart/form-data
```

**Form Data:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | File | Yes | File to upload (any type) |

#### Response

**Success (200):**
```json
{
  "success": true,
  "fileName": "1758346198562-hxszjt2iw6w.pdf",
  "downloadUrl": "https://YOUR_FILE_UPLOAD_API.workers.dev/file/1758346198562-hxszjt2iw6w.pdf",
  "supabaseUrl": "https://YOUR_PROJECT.supabase.co/storage/v1/object/public/files/1758346198562-hxszjt2iw6w.pdf",
  "originalName": "document.pdf",
  "size": 245678,
  "type": "application/pdf"
}
```

**Error (400):**
```json
{
  "error": "No file provided"
}
```

**Error (500):**
```json
{
  "error": "Upload failed",
  "details": "Error message"
}
```

---

### GET /file/{fileName}

**URL:** `https://YOUR_FILE_UPLOAD_API.workers.dev/file/{fileName}`

**Purpose:** Get information about an uploaded file

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `fileName` | string | Yes | The generated file name from upload |

#### Response

**Success (200):**
```json
{
  "fileName": "1758346198562-hxszjt2iw6w.pdf",
  "downloadUrl": "https://YOUR_PROJECT.supabase.co/storage/v1/object/public/files/1758346198562-hxszjt2iw6w.pdf",
  "fileInfo": {
    "id": "0859d6a3-1c5f-4b3b-b273-74677d044ff3",
    "name": "1758346198562-hxszjt2iw6w.pdf",
    "size": 245678,
    "content_type": "application/pdf",
    "created_at": "2025-09-20T05:29:58.980Z",
    "last_modified": "2025-09-20T05:29:58.980Z"
  }
}
```

**Error (404):**
```json
{
  "error": "File not found"
}
```

---

## 🔧 Configuration

### Data Transmitter Worker

**File:** `wrangler.toml`

```toml
name = "data-transmitter"
main = "worker.js"
compatibility_date = "2024-01-01"

[[durable_objects.bindings]]
name = "DATA_BROADCASTER"
class_name = "DataBroadcaster"
```

### File Upload Worker

**File:** `file-upload-wrangler.toml`

```toml
name = "file-upload-api"
main = "file-upload-worker.js"
compatibility_date = "2024-01-01"

[vars]
SUPABASE_URL = "https://YOUR_PROJECT.supabase.co"
# SUPABASE_ANON_KEY should not be committed. Set it via:
#   wrangler secret put SUPABASE_ANON_KEY
```

---

## 🚦 CORS Policy

All endpoints support CORS with the following headers:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

---

## 🔑 Authentication

Currently **NO AUTHENTICATION** is implemented. All endpoints are publicly accessible.

**⚠️ Security Considerations:**
- File uploads are public and accessible to anyone with the URL
- WebSocket connections have no authentication
- Consider implementing API keys or JWT tokens for production

---

## 📈 Rate Limits & Constraints

| Service | Constraint | Value |
|---------|------------|-------|
| WebSocket | Max connections per Durable Object | Unlimited (memory bound) |
| File Upload | Max file size | ~100MB (Cloudflare limit) |
| File Upload | File name format | `{timestamp}-{random}.{extension}` |
| Broadcast | Max message size | ~1MB (practical limit) |

---

## 🧪 Testing Endpoints

Use the provided `wss_tester.py` tool for testing:

```bash
# Test WebSocket connection
python3 wss_tester.py listen

# Test broadcast
python3 wss_tester.py broadcast '{"device":"test","format":"test","content":"Hello"}'

# Test file upload
python3 wss_tester.py upload file.pdf

# Run full test suite
python3 wss_tester.py test

# Start GUI tester
python3 wss_tester.py gui
```

---

## 📊 Response Status Codes

| Code | Meaning | Used For |
|------|---------|----------|
| **101** | Switching Protocols | WebSocket upgrade |
| **200** | Success | All successful operations |
| **400** | Bad Request | Invalid input/JSON |
| **404** | Not Found | Unknown endpoint or file |
| **500** | Server Error | Internal failures |

---

## 💡 Quick Integration Examples

### JavaScript WebSocket Client

```javascript
const ws = new WebSocket('wss://YOUR_DATA_TRANSMITTER.workers.dev');

ws.onopen = () => {
  console.log('Connected - ready to receive broadcasts');
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Broadcast received:', data);
};
```

### JavaScript File Upload

```javascript
const formData = new FormData();
formData.append('file', fileInput.files[0]);

const response = await fetch('https://YOUR_FILE_UPLOAD_API.workers.dev/upload', {
  method: 'POST',
  body: formData
});

const result = await response.json();
console.log('Upload result:', result);
```

### Python Broadcast

```python
import requests

data = {
  "device": "python-client",
  "format": "notification",
  "content": "Hello from Python"
}

response = requests.post(
  'https://YOUR_DATA_TRANSMITTER.workers.dev/broadcast',
  json=data
)

print(response.json())
```

---

## 📝 Notes

- All timestamps should be Unix timestamps in milliseconds
- File names are automatically generated to prevent collisions
- WebSocket connections only receive NEW broadcasts after they connect
- To get the latest data, use the GET /latest endpoint
- Broadcast messages are sent to ALL connected clients
- Files are stored publicly in Supabase Storage
- No message queuing - clients must be connected to receive broadcasts

---

*Last Updated: September 2025*
*Version: 1.1.0*
*Change: WebSocket connections no longer auto-receive latest data on connect*