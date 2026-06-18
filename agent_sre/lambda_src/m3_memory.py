"""대화 기억(메모리) 헬퍼 — Strands S3SessionManager 기반 (완성품).

학생은 agent_app.py 에서 `session_manager=m3_memory.memory(session_id)` 한 줄만
넣으면 됩니다. 세션 대화 상태가 S3에 자동 저장·복원되어, 호출(턴)을 넘어 기억합니다.
"""
import os

from strands.session.s3_session_manager import S3SessionManager

REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
SESSION_BUCKET = os.environ.get("SESSION_BUCKET")


def memory(session_id: str):
    """세션 기억 매니저를 만들어 반환합니다(설정이 없으면 None = 기억 없음)."""
    if not session_id or not SESSION_BUCKET:
        return None
    return S3SessionManager(
        session_id=session_id,
        bucket=SESSION_BUCKET,
        prefix="copilot-sessions/",
        region_name=REGION,
    )
