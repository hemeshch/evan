# Evan Protocol Specification

## Overview

This document specifies the communication protocol between Evan components:
- **User Device**: The end-user's interface (web app, mobile app, etc.)
- **Evan Server**: WebSocket server for real-time communication
- **Evan Client**: AI agent client that processes prompts and manages tools
- **File Upload Service**: Supabase-backed file storage service

## Architecture

```
User Device <--WebSocket--> Evan Server <--WebSocket--> Evan Client
     |                                                          |
     +------------------- File Upload API <--------------------+
```

## Message Format

All messages follow this general structure:

```json
{
  "recipient": "<target>",      // "agent", "user_device", or "all"
  "type": "<message_type>",     // Type of message
  "payload": {                  // Message-specific data
    // ...
  },
  "timestamp": 1234567890000     // Optional: Unix timestamp in milliseconds
}
```

## Message Types

### 1. New Prompt (Server → Agent)

Sent when a user submits a prompt for the AI agent to process.

```json
{
  "recipient": "agent",
  "type": "new_prompt",
  "payload": {
    "conversation_id": "uuid_string",
    "prompt": "User's question or command here"
  }
}
```

**Fields:**
- `conversation_id`: Unique identifier for the conversation
- `prompt`: The user's input text

**Agent Behavior:**
1. Creates new conversation if `conversation_id` is new
2. Processes prompt with Claude and available tools
3. Sends response back via `agent_response` message

### 2. Agent Response (Agent → User Device)

Sent when the agent completes processing a prompt.

```json
{
  "device": "evan",
  "format": "agent_response",
  "recipient": "user_device",
  "type": "agent_response",
  "payload": {
    "conversation_id": "uuid_string",
    "prompt": "Agent's response text here"
  },
  "timestamp": 1234567890000
}
```

**Fields:**
- `conversation_id`: Same as received in `new_prompt`
- `prompt`: The agent's response text
- `timestamp`: When the response was generated

### 3. Agent File Upload (Agent → User Device)

Sent when the agent uploads a file for the user to download.

```json
{
  "device": "evan",
  "format": "file_upload",
  "recipient": "user_device",
  "type": "agent_file_upload",
  "payload": {
    "conversation_id": "uuid_string",
    "resource_url": "https://YOUR_FILE_UPLOAD_API.workers.dev/file/1234-abc.pdf",
    "description": "Natural language description of the file and its purpose"
  },
  "timestamp": 1234567890000
}
```

**Fields:**
- `conversation_id`: Conversation this file belongs to
- `resource_url`: Direct download URL for the file
- `description`: Human-readable description of the file

**User Device Behavior:**
- Display download link or auto-download
- Show description to user
- Associate file with conversation

## Agent Tools Protocol

### Tool Execution Context

When tools are executed, they receive:
- `conversation_id`: Current conversation
- `working_directory`: Agent's working directory path
- Tool-specific parameters

### File Management Rules

1. **Working Directory Structure:**
   ```
   agent-working-directory/{conversation_id}/
   ├── agent_memory/        → symlink to shared memory
   ├── conversation_data/   → symlink to conversation-specific data
   └── temp/                → temporary files
   ```

2. **Upload Restrictions:**
   - Files MUST be in `conversation_data/` folder to be uploaded
   - Path must start with `conversation_data/`
   - Security checks prevent path traversal

3. **Tool Access Patterns:**
   - `list_files`: Can list any directory within working directory
   - `get_lego_castle`: Can save to any path within working directory
   - `submit_file_to_user`: Only accepts files from `conversation_data/`

## Connection Flow

### 1. Client Connection
```
Client → [WebSocket Connect] → Server
Server → [Connection Established] → Client
```

### 2. Prompt Processing
```
User Device → [new_prompt] → Server → Agent
Agent → [processes with tools] → Internal
Agent → [agent_response] → Server → User Device
```

### 3. File Upload Flow
```
Agent → [saves file to conversation_data/] → Local Storage
Agent → [uploads via HTTP POST] → File Upload API
File Upload API → [returns download URL] → Agent
Agent → [agent_file_upload broadcast] → Server → User Device
```

## State Management

### Per-Conversation State
Each conversation maintains:
- Message history
- Tool execution state
- Working directory
- Uploaded files list

### Global State
Shared across all conversations:
- Tool usage statistics
- Shared agent memory
- System configuration

## Security Considerations

### Path Traversal Protection
All file operations validate paths to ensure:
- Relative paths only (no absolute paths)
- No `../` traversal sequences
- Operations confined to working directory

### File Upload Security
- Files must originate from `conversation_data/`
- Upload size limits enforced by Cloudflare (100MB)
- File type validation on upload

### WebSocket Security
- Currently no authentication (planned for future)
- SSL/TLS encryption for all connections
- Rate limiting at Cloudflare edge

## Error Handling

### Tool Errors
Tools return errors to the agent as:
```python
return None, "Error: Description of what went wrong"
```

Agent receives error and can:
- Retry with different parameters
- Inform user of the issue
- Try alternative approach

### Connection Errors
- Automatic reconnection with exponential backoff
- Message queuing during disconnection (future)
- State persistence across restarts

## Future Enhancements

### Planned Features
1. **Authentication**: JWT or API key based auth
2. **Message Queue**: Persistent message delivery
3. **File Streaming**: Large file support
4. **Progress Updates**: Real-time tool execution updates
5. **Multi-Modal**: Image/audio message support

### Protocol Versioning
Future versions will include:
```json
{
  "version": "1.0",
  "recipient": "...",
  "type": "...",
  "payload": {}
}
```

## Example Conversation Flow

```json
// 1. User asks for a file
→ {
  "recipient": "agent",
  "type": "new_prompt",
  "payload": {
    "conversation_id": "conv-123",
    "prompt": "Can you get me the lego castle STL file?"
  }
}

// 2. Agent processes and saves file
// (Internal: Agent uses get_lego_castle tool)
// (Internal: Agent saves to conversation_data/castle.stl)
// (Internal: Agent uses submit_file_to_user tool)

// 3. Agent sends response
→ {
  "recipient": "user_device",
  "type": "agent_response",
  "payload": {
    "conversation_id": "conv-123",
    "prompt": "I've retrieved the lego castle STL file for you. It's ready for download."
  }
}

// 4. Agent sends file notification
→ {
  "recipient": "user_device",
  "type": "agent_file_upload",
  "payload": {
    "conversation_id": "conv-123",
    "resource_url": "https://file-upload-api.../file/castle.stl",
    "description": "Lego castle STL file for 3D printing"
  }
}
```

## Implementation Notes

### Python Client Implementation
```python
# Receiving prompts
def handle_prompt(message: Dict[str, Any]):
    payload = message.get("payload", {})
    conversation_id = payload.get("conversation_id")
    prompt = payload.get("prompt")

    # Process with Claude and tools
    response = process_with_agent(prompt, conversation_id)

    # Send response
    websocket.send_response(conversation_id, response)
```

### JavaScript Client Implementation
```javascript
// Listening for file uploads
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);

  if (data.type === 'agent_file_upload') {
    const { conversation_id, resource_url, description } = data.payload;
    // Display download link to user
    showDownload(conversation_id, resource_url, description);
  }
};
```

## Testing

### Test Endpoints
- WebSocket: `wss://YOUR_DATA_TRANSMITTER.workers.dev`
- Broadcast: `https://YOUR_DATA_TRANSMITTER.workers.dev/broadcast`
- File Upload: `https://YOUR_FILE_UPLOAD_API.workers.dev/upload`

### Test Commands
```bash
# Test WebSocket connection
python wss_tester.py listen

# Test broadcast
python wss_tester.py broadcast '{"recipient":"agent","type":"new_prompt","payload":{"conversation_id":"test","prompt":"Hello"}}'

# Test file upload
python test_upload_broadcast.py
```

---

*Protocol Version: 1.0*
*Last Updated: September 2025*
*Status: Active Development*