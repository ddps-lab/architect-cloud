"""채팅 런타임 (FastAPI + SSE). 학생은 건드리지 않습니다.

학생이 작성한 solution.build_agent(session_id) 를 호출해 에이전트를 만들고,
도구 호출 트레이스와 답변 토큰을 SSE로 스트리밍합니다. Lambda Web Adapter 뒤에서
Function URL(RESPONSE_STREAM)로 서빙됩니다.

POST /chat  body: {"message": "...", "session_id": "..."}  -> text/event-stream
GET  /      -> readiness
"""
import json

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse

import solution  # 🎓 학생이 작성하는 파일

app = FastAPI()


@app.get("/")
def health():
    return {"ok": True}


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

    async def gen():
        seen_tools = set()
        try:
            agent = solution.build_agent(session_id)
            async for event in agent.stream_async(message):
                tu = event.get("current_tool_use") if isinstance(event, dict) else None
                if tu and tu.get("name"):
                    tid = tu.get("toolUseId") or tu.get("name")
                    if tid not in seen_tools:
                        seen_tools.add(tid)
                        yield _sse({"type": "tool", "name": tu.get("name"), "input": tu.get("input")})
                if isinstance(event, dict) and event.get("data"):
                    yield _sse({"type": "text", "delta": event["data"]})
            yield _sse({"type": "done"})
        except Exception as e:  # noqa: BLE001
            yield _sse({"type": "error", "message": f"{type(e).__name__}: {e}"})

    return StreamingResponse(gen(), media_type="text/event-stream")
