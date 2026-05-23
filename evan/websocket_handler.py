import websocket
import json
import threading
import time
import requests
import ssl
import certifi
from typing import Callable, Optional, Dict, Any
from datetime import datetime
from urllib.parse import urlencode, urlparse, urlunparse, parse_qsl
from .constants import WEBSOCKET_SERVER_URL, BROADCAST_API_URL, LATEST_API_URL, BROADCAST_TOKEN


_CA_BUNDLE = certifi.where()


def _with_role(url: str, role: str) -> str:
    """Return url with `role=` added to the query string if not already set."""
    parsed = urlparse(url)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    query.setdefault("role", role)
    return urlunparse(parsed._replace(query=urlencode(query)))


def _broadcast_headers() -> Dict[str, str]:
    """Authorization headers for /broadcast (empty when no token configured)."""
    if BROADCAST_TOKEN:
        return {"Authorization": f"Bearer {BROADCAST_TOKEN}"}
    return {}


class WebSocketHandler:
    def __init__(self, url: str = None):
        # The Cloudflare DataBroadcaster Worker requires a role on connect
        # so it can route messages by recipient instead of fanning out.
        self.url = _with_role(url or WEBSOCKET_SERVER_URL, "agent")
        self.ws = None
        self.connected = False
        self.message_handler: Optional[Callable[[Dict[str, Any]], None]] = None
        self.reconnect_delay = 5
        self.should_run = True
        self.thread = None

    def set_message_handler(self, handler: Callable[[Dict[str, Any]], None]):
        self.message_handler = handler

    def connect(self):
        if self.thread is not None and self.thread.is_alive():
            return
        self.should_run = True
        self.thread = threading.Thread(target=self._run)
        self.thread.daemon = True
        self.thread.start()

    def _run(self):
        while self.should_run:
            try:
                ssl_opt = {
                    "cert_reqs": ssl.CERT_REQUIRED,
                    "ca_certs": _CA_BUNDLE,
                }

                self.ws = websocket.WebSocketApp(
                    self.url,
                    on_open=self._on_open,
                    on_message=self._on_message,
                    on_error=self._on_error,
                    on_close=self._on_close
                )
                self.ws.run_forever(sslopt=ssl_opt)

                if self.should_run:
                    print(f"WebSocket disconnected. Reconnecting in {self.reconnect_delay} seconds...")
                    time.sleep(self.reconnect_delay)

            except Exception as e:
                print(f"WebSocket connection error: {e}")
                if self.should_run:
                    time.sleep(self.reconnect_delay)

    def _on_open(self, ws):
        self.connected = True
        print(f"Connected to WebSocket server at {self.url}")

    def _on_message(self, ws, message):
        try:
            data = json.loads(message)

            if data.get('recipient') == 'agent' and data.get('type') == 'new_prompt':
                if self.message_handler:
                    self.message_handler(data)
                else:
                    print(f"Received message but no handler set: {data}")

        except json.JSONDecodeError as e:
            print(f"Failed to parse message: {e}")
        except Exception as e:
            print(f"Error handling message: {e}")

    def _on_error(self, ws, error):
        print(f"WebSocket error: {error}")

    def _on_close(self, ws, close_status_code, close_msg):
        self.connected = False
        print(f"WebSocket connection closed: {close_status_code} - {close_msg}")

    def disconnect(self):
        self.should_run = False
        if self.ws:
            self.ws.close()
        if self.thread:
            self.thread.join(timeout=5)

    def send_response(self, conversation_id: str, response: str) -> bool:
        broadcast_url = BROADCAST_API_URL

        data = {
            "device": "evan",
            "format": "agent_response",
            "recipient": "user_device",
            "type": "agent_response",
            "payload": {
                "conversation_id": conversation_id,
                "prompt": response
            },
            "timestamp": int(datetime.now().timestamp() * 1000)
        }

        try:
            response = requests.post(
                broadcast_url,
                json=data,
                headers=_broadcast_headers(),
                verify=_CA_BUNDLE,
            )
            response.raise_for_status()
            return True
        except Exception as e:
            print(f"Failed to send response: {e}")
            return False

    def broadcast_tool_call(self, conversation_id: str, tool_name: str, display_name: Optional[str] = None, parameters: Optional[Dict] = None) -> bool:
        """Broadcast a tool call notification to the user device.

        Args:
            conversation_id: The conversation ID
            tool_name: The name of the tool being called
            display_name: Human-readable display name for the tool
            parameters: Optional parameters dict (for future use)

        Returns:
            True if broadcast successful, False otherwise
        """
        broadcast_url = BROADCAST_API_URL

        data = {
            "device": "evan",
            "format": "tool_call",
            "recipient": "user_device",
            "type": "tool_call",
            "payload": {
                "conversation_id": conversation_id,
                "tool_name": tool_name,
                "display_name": display_name if display_name else tool_name,
                "timestamp": datetime.now().isoformat()
            },
            "timestamp": int(datetime.now().timestamp() * 1000)
        }

        try:
            response = requests.post(
                broadcast_url,
                json=data,
                headers=_broadcast_headers(),
                verify=_CA_BUNDLE,
            )
            response.raise_for_status()
            print(f"📡 Broadcast tool call: {tool_name}")
            return True
        except Exception as e:
            print(f"Failed to broadcast tool call: {e}")
            return False

    def get_latest_data(self) -> Optional[Dict[str, Any]]:
        latest_url = LATEST_API_URL

        try:
            response = requests.get(latest_url, verify=_CA_BUNDLE)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"Failed to get latest data: {e}")
            return None