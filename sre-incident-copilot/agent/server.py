"""FastAPI app served via the Lambda Web Adapter for response STREAMING.

Native Lambda response streaming is Node-only; for this Python/Strands agent we
run a tiny FastAPI app behind the Lambda Web Adapter (AWS_LWA_INVOKE_MODE=
response_stream) on a Function URL (InvokeMode RESPONSE_STREAM).

POST /chat  body: {"message": "...", "session_id": "..."}
  -> text/event-stream (SSE), one JSON object per event:
       {"type":"module","module":"m2"}
       {"type":"tool","name":"get_logs","input":{...}}      # a tool was called
       {"type":"text","delta":"..."}                         # streamed answer text
       {"type":"done"}
       {"type":"error","message":"..."}

GET /  -> readiness check (LWA pings this).
"""
import json
import os

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse

from .agent import build_agent_for_module

_MODULE = os.environ.get("MODULE", "m4")

app = FastAPI()


@app.get("/")
def health():
    return {"ok": True, "module": _MODULE}


def _sse(obj: dict) -> str:
    return f"data: {json.dumps(obj, ensure_ascii=False)}\n\n"


@app.post("/chat")
async def chat(request: Request):
    try:
        data = await request.json()
    except Exception:  # noqa: BLE001
        return JSONResponse({"error": "invalid JSON body"}, status_code=400)

    message = (data.get("message") or "").strip()
    session_id = (data.get("session_id") or "default").strip()
    if not message:
        return JSONResponse({"error": "message is required"}, status_code=400)

    # Build per request so the S3 session manager loads this session's prior
    # state (M3+). For m1/m2 (no memory) this is just a fresh stateless agent.
    agent = build_agent_for_module(_MODULE, session_id=session_id)

    async def gen():
        yield _sse({"type": "module", "module": _MODULE})
        seen_tools = set()
        try:
            async for event in agent.stream_async(message):
                # A tool is being invoked — surface it as a trace entry.
                tu = event.get("current_tool_use") if isinstance(event, dict) else None
                if tu and tu.get("name"):
                    tid = tu.get("toolUseId") or tu.get("name")
                    if tid not in seen_tools:
                        seen_tools.add(tid)
                        yield _sse({"type": "tool", "name": tu.get("name"), "input": tu.get("input")})
                # Streamed answer text.
                if isinstance(event, dict) and event.get("data"):
                    yield _sse({"type": "text", "delta": event["data"]})
            yield _sse({"type": "done"})
        except Exception as e:  # noqa: BLE001
            yield _sse({"type": "error", "message": f"{type(e).__name__}: {e}"})

    return StreamingResponse(gen(), media_type="text/event-stream")
