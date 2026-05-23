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

The anon key must not live in source. Set it as a worker secret instead:

```bash
wrangler secret put SUPABASE_ANON_KEY --config file-upload-wrangler.toml
# paste the anon key from step 1 when prompted
```

### 2c. Deploy both workers

```bash
wrangler deploy --config wrangler.toml              # the data-transmitter
wrangler deploy --config file-upload-wrangler.toml  # the file-upload-api
```

After each deploy, `wrangler` prints the worker's public URL. Save both:

- WebSocket / broadcast: `https://YOUR_DATA_TRANSMITTER.workers.dev`
- File upload: `https://YOUR_FILE_UPLOAD_API.workers.dev`

### 2d. Smoke test

Open `server/websocket-test.html` in a browser (edit the URLs at line ~114 first to point at your data-transmitter). You should see "Connected." If you don't, the rest of Evan won't work either — debug here before moving on.

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
```

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
2. Open `mobile/evanai-mobile/Configuration.swift` and replace the four placeholder URLs with your worker URLs from step 2.
3. In Xcode, select a simulator target (e.g., iPhone 15) and hit ⌘R. The app should connect to your data-transmitter automatically.
4. To run on a real iPhone, select your device, set a development team under **Signing & Capabilities**, and build. You'll need a (free) Apple ID for sideloading; a paid Apple Developer account for distribution.

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
| iOS app says "Disconnected"                  | Worker URL in `Configuration.swift` doesn't match what `wrangler deploy` printed. Hit the URL in a browser to confirm it's live. |
| `zsh` tool errors with "Cannot connect to Docker daemon" | Docker Desktop isn't running, or the agent image hasn't been built. See step 4. |
| File upload fails                            | The Supabase `files` bucket isn't public, or `SUPABASE_ANON_KEY` wasn't set via `wrangler secret put`. |
| `pip install` fails on a native package      | See the brew commands under step 3.                       |

---

## Configuration reference

### Environment variables (Python client)

| Variable                | Required | Default                                | Purpose                            |
|-------------------------|----------|----------------------------------------|------------------------------------|
| `ANTHROPIC_API_KEY`     | yes      | —                                      | Claude API access                  |
| `WEBSOCKET_SERVER_URL`  | yes      | (placeholder)                          | data-transmitter Worker, ws scheme |
| `BROADCAST_API_URL`     | yes      | (placeholder)                          | data-transmitter `/broadcast`      |
| `LATEST_API_URL`        | yes      | (placeholder)                          | data-transmitter `/latest`         |
| `FILE_UPLOAD_API_URL`   | yes      | (placeholder)                          | file-upload-api `/upload`          |
| `EVAN_RUNTIME_DIR`      | no       | `./evan_runtime`                       | Where conversations + state live   |
| `EVAN_SHORTCUTS_DIR`    | no       | `~/evan/shortcut-tools`                | Apple Shortcuts helper scripts     |
| `CLAUDE_MODEL`          | no       | `claude-opus-4-1-20250805`             | Claude model ID                    |

### Worker secrets (`wrangler secret put ...`)

| Secret                  | Worker            | Purpose                            |
|-------------------------|-------------------|------------------------------------|
| `SUPABASE_ANON_KEY`     | file-upload-api   | Authenticates uploads to Supabase  |
