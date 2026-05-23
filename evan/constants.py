"""Constants for Evan Client."""

import os

# Server endpoints. Set these in your .env (see .env.template) to point at
# your own deployment of the Cloudflare Workers in server/.
WEBSOCKET_SERVER_URL = os.environ.get(
    "WEBSOCKET_SERVER_URL",
    "wss://YOUR_DATA_TRANSMITTER.workers.dev",
)
BROADCAST_API_URL = os.environ.get(
    "BROADCAST_API_URL",
    "https://YOUR_DATA_TRANSMITTER.workers.dev/broadcast",
)
LATEST_API_URL = os.environ.get(
    "LATEST_API_URL",
    "https://YOUR_DATA_TRANSMITTER.workers.dev/latest",
)
FILE_UPLOAD_API_URL = os.environ.get(
    "FILE_UPLOAD_API_URL",
    "https://YOUR_FILE_UPLOAD_API.workers.dev/upload",
)

# Default configurations
DEFAULT_RUNTIME_DIR = "evan_runtime"
DEFAULT_CLAUDE_MODEL = "claude-opus-4-1-20250805"
BACKUP_CLAUDE_MODEL = "claude-sonnet-4-20250514"
MAX_TOKENS = 32000

# Retry configuration
MAX_BACKOFF_SECONDS = 3  # Maximum backoff duration
INITIAL_BACKOFF_SECONDS = 0.1  # Initial backoff duration
BACKOFF_MULTIPLIER = 2  # Exponential multiplier
FALLBACK_RETRY_COUNT = 10  # Number of retries before switching to backup model
# No limit to total retries - will keep retrying indefinitely