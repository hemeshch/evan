# Setting up Evan

Evan has three components that talk to each other:

```
   ┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
   │  iOS app         │ ◄─────► │  Cloudflare      │ ◄─────► │  Python client   │
   │  (mobile/)       │   ws    │  Workers         │   ws    │  (evan/)         │
   │                  │         │  (server/)       │         │                  │
   │  Sends prompts,  │         │                  │         │  Runs the agent  │
   │  receives        │         │  + Supabase for  │         │  on your Mac,    │
   │  responses       │         │  file uploads    │         │  invokes Claude  │
   └──────────────────┘         └──────────────────┘         └──────────────────┘
```

You'll set them up in this order: **Supabase → Cloudflare Workers → Python client → (optional) Docker agent container → iOS app**. Each step's outputs become the next step's inputs.

Plan on 60–90 minutes the first time through.

---

## Prerequisites

| Component    | You need                                                              |
|--------------|-----------------------------------------------------------------------|
| Server       | A Cloudflare account, a Supabase account, Node.js 18+, `wrangler` CLI |
| Client       | macOS, Python 3.10+, an Anthropic API key                             |
| Container    | Docker Desktop (only if you want the in-container `zsh` tool)         |
| Mobile       | macOS, Xcode 16+, an Apple ID (a paid Developer account if you want to run on a real device) |

Install the CLIs:

```bash
brew install python@3.12 node
npm install -g wrangler
```

Grab your Anthropic API key: <https://console.anthropic.com/account/keys>.

---

## 1. Supabase (file storage)

1. Create a new project at <https://supabase.com/dashboard>. Pick any region. Save the database password somewhere — you won't need it for Evan, but Supabase forces you to set one.
2. Once the project is provisioned, go to **Storage** in the left nav.
3. Click **New bucket**, name it `files`, and toggle **Public bucket** on. (Evan uploads files here and serves them by URL.)
4. Go to **Project Settings → API** and copy two values:
   - **Project URL** (something like `https://xxxxxxxxxxx.supabase.co`)
   - **anon `public` key** (a long JWT starting with `eyJ...`)

Keep this tab open — you'll paste these into the worker config next.

---

## 2. Cloudflare Workers (×2)

The `server/` directory contains two separate Workers. They're independent and get deployed with two different `wrangler.toml` configs.

### 2a. Log in and pick worker names

```bash
cd server
wrangler login
```

Decide on two subdomain names — they need to be unique across all Cloudflare accounts. For the rest of these docs, replace `YOUR_DATA_TRANSMITTER` and `YOUR_FILE_UPLOAD_API` with whatever you choose.

Edit `server/wrangler.toml` and change the `name` field to your data-transmitter name. Edit `server/file-upload-wrangler.toml` and change the `name` field to your file-upload-api name; while you're in there, set the two `[vars]` values:

```toml
[vars]
SUPABASE_URL = "https://YOUR_PROJECT.supabase.co"      # from step 1
PUBLIC_BASE_URL = "https://YOUR_FILE_UPLOAD_API.workers.dev"
```

### 2b. Set the Supabase secret

The Supabase service-role key must not live in source. Set it as a worker secret:

```bash
wrangler secret put SUPABASE_SERVICE_KEY --config file-upload-wrangler.toml
# paste the service_role key from Project Settings → API when prompted
```

> The file-upload Worker uses the service key server-side so your storage RLS
> does not need to permit anonymous writes. If you only have the anon key
> handy, you can fall back to `wrangler secret put SUPABASE_ANON_KEY` — the
> worker accepts it with a `console.warn`, but this is not recommended.

### 2c. Set the broadcast token (strongly recommended)

Without an auth token, anyone on the internet who finds your data-transmitter
URL can POST to `/broadcast` and inject `new_prompt` messages that drive the
agent. Generate a long random token and set it on the Worker:

```bash
# Pick any high-entropy string (32+ chars):
openssl rand -hex 32
# Then save it as a secret on the data-transmitter Worker:
wrangler secret put BROADCAST_TOKEN --config wrangler.toml
# paste the same string when prompted
```

You'll set the same value in your Python client's `.env` in step 3.

### 2d. Deploy both workers

```bash
wrangler deploy --config wrangler.toml              # the data-transmitter
wrangler deploy --config file-upload-wrangler.toml  # the file-upload-api
```

After each deploy, `wrangler` prints the worker's public URL. Save both:

- WebSocket / broadcast: `https://YOUR_DATA_TRANSMITTER.workers.dev`
- File upload: `https://YOUR_FILE_UPLOAD_API.workers.dev`

### 2e. Wire-protocol notes

The data-transmitter Worker now requires a `role` on every WebSocket
upgrade so it can route messages by `recipient` instead of fanning out
to all sockets:

- Python client connects to `wss://.../?role=agent`
- iOS client connects to `wss://.../?role=user_device`

The Python client (`evan/websocket_handler.py`) adds the `role` parameter
automatically. If you're rolling a custom client, append it yourself —
the Worker rejects connections without a valid role with HTTP 400.

### 2f. Smoke test

Open `server/websocket-test.html` in a browser (edit the URLs at line ~114 first to point at your data-transmitter, and append `?role=user_device` to the WebSocket URL). You should see "Connected." If you don't, the rest of Evan won't work either — debug here before moving on.

---

## 3. Python client

From the repo root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install -e .
```

> ⚠️ `requirements.txt` is heavy (~3 GB installed) and includes packages with native deps. If `pip install` fails, the usual culprits are:
> - `pygraphviz` → `brew install graphviz`
> - `pdf2image` → `brew install poppler`
> - `pytesseract` → `brew install tesseract`
> - `camelot-py` → `brew install ghostscript tcl-tk`
>
> If the system deps are too much hassle, use the minimal install instead:
>
> ```bash
> pip install -r requirements-minimal.txt
> pip install -e .
> ```
>
> That's enough to boot `evan run` and use the default-enabled tools (filesystem, upload, memory, view-photo, container `zsh`). You can add the heavier packages back later when you want the full document-processing stack inside the agent's sandbox.

### 3a. Configure environment

```bash
cp .env.template .env
```

Open `.env` and fill in:

```dotenv
ANTHROPIC_API_KEY=sk-ant-...

WEBSOCKET_SERVER_URL=wss://YOUR_DATA_TRANSMITTER.workers.dev
BROADCAST_API_URL=https://YOUR_DATA_TRANSMITTER.workers.dev/broadcast
LATEST_API_URL=https://YOUR_DATA_TRANSMITTER.workers.dev/latest
FILE_UPLOAD_API_URL=https://YOUR_FILE_UPLOAD_API.workers.dev/upload

# Required if you set BROADCAST_TOKEN on the data-transmitter Worker in 2c.
# Must match the value you passed to `wrangler secret put BROADCAST_TOKEN`.
EVAN_BROADCAST_TOKEN=
```

> The Python client appends `?role=agent` to `WEBSOCKET_SERVER_URL`
> automatically — leave the URL itself parameter-free.

### 3b. Run it

```bash
evan run
```

You should see the client connect to the WebSocket. Test that the agent itself works without going through the iOS app:

```bash
evan test-prompt "what's 2+2?"
```

If you see a Claude response, the Python side is healthy.

---

## 4. Docker agent container (optional)

This step is only required if you want the `zsh` tool — which gives the agent a sandboxed Ubuntu environment with LibreOffice, Pandoc, Python data-science libs, etc. for creating documents and processing media. Without it, file/web/photo/memory tools still work; only `zsh` will fail if invoked.

```bash
cd evan/tools/linux_desktop_environment
./scripts/build-agent.sh
```

The build takes 10–20 minutes the first time and produces a `claude-agent:latest` Docker image (~5 GB).

Verify with:

```bash
./scripts/verify.sh
```

If you don't have Docker installed and don't want it, edit `evan/enabled_tools.py` and comment out `ContainerZshToolProvider` from `ENABLED_TOOLS`.

---

## 5. iOS app

1. Open `mobile/evanai-mobile.xcodeproj` in Xcode (16 or newer).
2. Open `mobile/evanai-mobile/Configuration.swift` and replace the four placeholder URLs with your worker URLs from step 2. The WebSocket URL must include `?role=user_device` — e.g., `wss://YOUR_DATA_TRANSMITTER.workers.dev/?role=user_device`. The Worker rejects sockets without a role.
3. If you set `BROADCAST_TOKEN` on the Worker in 2c, configure the iOS client to send `Authorization: Bearer <token>` on any direct `POST /broadcast` calls (uploads + tool-result echoes). Without it, the Worker returns 401.
4. In Xcode, select a simulator target (e.g., iPhone 15) and hit ⌘R. The app should connect to your data-transmitter automatically.
5. To run on a real iPhone, select your device, set a development team under **Signing & Capabilities**, and build. You'll need a (free) Apple ID for sideloading; a paid Apple Developer account for distribution.

The voice features (Cartesia for STT, Apple Foundation Models on-device) require iOS 18.1+ on a device with Apple Intelligence. They're not required for the chat path.

---

## Verifying end-to-end

With `evan run` going on your Mac:

1. Open the iOS app.
2. Type a prompt like *"list the files on my Desktop"*.
3. Within a few seconds the Mac terminal should show the agent receiving the message, calling tools, and the iOS app should show the response.

If anything in that chain is silent, the troubleshooting section below tells you where to start.

---

## Troubleshooting

| Symptom                                      | Likely cause                                              |
|----------------------------------------------|-----------------------------------------------------------|
| `evan run` exits immediately                 | Missing `ANTHROPIC_API_KEY` in `.env`                     |
| `[shortcuts] Directory not found...`         | Expected if you don't have the Apple Shortcuts helpers; safe to ignore. Set `EVAN_SHORTCUTS_DIR` to enable. |
| Either client gets WebSocket 400 on connect  | URL is missing `?role=agent` (Python) or `?role=user_device` (iOS). The Worker rejects role-less upgrades since the protocol changes. |
| Broadcasts return 401                        | `BROADCAST_TOKEN` is set on the Worker but the client isn't sending `Authorization: Bearer ...`. Set `EVAN_BROADCAST_TOKEN` in `.env` (Python) or wire the header into iOS. |
| iOS app says "Disconnected"                  | Worker URL in `Configuration.swift` doesn't match what `wrangler deploy` printed, or is missing `?role=user_device`. Hit the URL in a browser to confirm it's live. |
| `zsh` tool errors with "Cannot connect to Docker daemon" | Docker Desktop isn't running, or the agent image hasn't been built. See step 4. |
| File upload fails                            | The Supabase `files` bucket isn't public, or `SUPABASE_SERVICE_KEY` wasn't set via `wrangler secret put`. |
| File upload succeeds but is rejected as wrong type | The file-upload Worker now whitelists Content-Type and falls back to `application/octet-stream`. If you need an extra MIME type, add it to `ALLOWED_CONTENT_TYPES` in `server/file-upload-worker.js`. |
| `evan debug` returns 401 on every request    | You set `EVAN_DEBUG_TOKEN` — send `Authorization: Bearer <token>` from the browser/Postman. |
| `pip install` fails on a native package      | See the brew commands under step 3.                       |

---

## Configuration reference

### Environment variables (Python client)

| Variable                  | Required | Default                                | Purpose                                                                 |
|---------------------------|----------|----------------------------------------|-------------------------------------------------------------------------|
| `ANTHROPIC_API_KEY`       | yes      | —                                      | Claude API access                                                       |
| `WEBSOCKET_SERVER_URL`    | yes      | (placeholder)                          | data-transmitter Worker, ws scheme. Client auto-appends `?role=agent`. |
| `BROADCAST_API_URL`       | yes      | (placeholder)                          | data-transmitter `/broadcast`                                           |
| `LATEST_API_URL`          | yes      | (placeholder)                          | data-transmitter `/latest`                                              |
| `FILE_UPLOAD_API_URL`     | yes      | (placeholder)                          | file-upload-api `/upload`                                               |
| `EVAN_BROADCAST_TOKEN`    | if Worker enforces it | —                         | Bearer token sent on `/broadcast` POSTs. Must match the Worker secret.  |
| `EVAN_DEBUG_TOKEN`        | when debug server is non-loopback | —             | Bearer token required by `evan debug` mutating + file routes.           |
| `EVAN_RUNTIME_DIR`        | no       | `./evan_runtime`                       | Where conversations + state live                                        |
| `EVAN_SHORTCUTS_DIR`      | no       | `~/evan/shortcut-tools`                | Apple Shortcuts helper scripts                                          |
| `CLAUDE_MODEL`            | no       | `claude-opus-4-1-20250805`             | Claude model ID                                                         |
| `CLAUDE_BACKUP_MODEL`     | no       | `claude-sonnet-4-20250514`             | Model used after `CLAUDE_FALLBACK_RETRY_COUNT` failures                 |
| `CLAUDE_MAX_RETRIES`      | no       | `30`                                   | Hard cap on retry attempts in the Claude streaming loop                 |
| `CLAUDE_MAX_RETRY_SECONDS`| no       | `900`                                  | Hard wall-clock budget (seconds) before the retry loop gives up         |

### Worker secrets (`wrangler secret put ...`)

| Secret                  | Worker            | Purpose                                                                                  |
|-------------------------|-------------------|------------------------------------------------------------------------------------------|
| `SUPABASE_SERVICE_KEY`  | file-upload-api   | Server-side write access to Supabase Storage. Preferred over the anon key.               |
| `SUPABASE_ANON_KEY`     | file-upload-api   | Fallback only — used with a warning if `SUPABASE_SERVICE_KEY` is unset.                  |
| `BROADCAST_TOKEN`       | data-transmitter  | Required bearer token on `POST /broadcast`. Without it, anyone can drive the agent.      |

### Debug server (`evan debug`)

The Flask debug UI is now loopback-only by default. To bind to a non-loopback
interface you **must** set `EVAN_DEBUG_TOKEN`, and clients must send
`Authorization: Bearer <token>` on every mutating + file-access route
(`/api/prompt`, `/api/tool/execute`, `/api/tool/stream/*`, `/api/reset`,
`/api/files/...`). The Werkzeug debugger is forced off in all cases —
do not re-enable it; it ships a remote code execution vector via the
debugger PIN.
