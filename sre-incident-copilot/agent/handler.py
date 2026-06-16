"""M6 — Lambda entrypoint exposed via API Gateway.

Contract:
  POST /chat   body: {"message": "...", "session_id": "..."}
  response:    {"reply": "...", "session_id": "...", "actions": [...]}

The chat web UI (web-chat/) posts here. session_id ties multi-turn incidents to
the DynamoDB timeline (M3). MCP is not loaded in Lambda (see mcp_setup.py).
"""
import json
import os

from .agent import build_agent_for_module

# Module level is set by the MODULE env var so the lab can progress (m1..m5) by
# just updating the Lambda's environment — no code change needed.
_MODULE = os.environ.get("MODULE", "m4")
# Build once per container (reused across warm invocations).
_AGENT = build_agent_for_module(_MODULE)

_CORS = {
    "Access-Control-Allow-Origin": os.environ.get("CORS_ORIGIN", "*"),
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
}


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json", **_CORS},
        "body": json.dumps(body),
    }


def handler(event, context):
    method = (event.get("requestContext", {}).get("http", {}) or {}).get("method", "POST")
    if method == "OPTIONS":
        return _resp(200, {"ok": True})

    try:
        body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            import base64

            body = base64.b64decode(body).decode("utf-8")
        data = json.loads(body)
    except Exception:  # noqa: BLE001
        return _resp(400, {"error": "invalid JSON body"})

    message = (data.get("message") or "").strip()
    session_id = (data.get("session_id") or "default").strip()
    if not message:
        return _resp(400, {"error": "message is required"})

    # Make the session id available to memory tools by prefixing the prompt.
    prompt = f"[session_id={session_id}]\n{message}"

    try:
        result = _AGENT(prompt)
        reply = str(result)
    except Exception as e:  # noqa: BLE001
        return _resp(500, {"error": f"agent error: {type(e).__name__}: {e}"})

    return _resp(200, {"reply": reply, "session_id": session_id, "module": _MODULE})
