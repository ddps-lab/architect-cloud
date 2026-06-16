"""M3 — Agent memory: carry an incident across turns and (in Lambda) across
stateless invocations.

Lambda loses in-process state between requests, so findings are persisted to a
DynamoDB table keyed by session_id. The agent records each finding as it goes and
recalls the timeline instead of re-investigating from scratch.

Tools:
  record_finding(session_id, step, detail)  - append to the incident timeline
  get_timeline(session_id)                   - recall everything found so far

Env: INCIDENT_TABLE (DynamoDB table, partition key "session_id", sort key "ts").
"""
import os
import time
from decimal import Decimal

import boto3
from strands import tool

REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
_TABLE_NAME = os.environ.get("INCIDENT_TABLE", "incident-timeline")
_ddb = boto3.resource("dynamodb", region_name=REGION)


def _table():
    return _ddb.Table(_TABLE_NAME)


@tool
def record_finding(session_id: str, step: str, detail: str) -> str:
    """Persist a finding to the incident timeline so it survives later turns.

    Args:
        session_id: the incident/chat session id.
        step: which loop stage, e.g. "detect" | "diagnose" | "recover" | "verify".
        detail: the concrete finding, e.g. "id column out-of-range, INT32 overflow".
    """
    ts = Decimal(str(time.time()))
    try:
        _table().put_item(
            Item={"session_id": session_id, "ts": ts, "step": step, "detail": detail}
        )
        return f"recorded [{step}] {detail}"
    except Exception as e:  # noqa: BLE001
        return f"failed to record finding: {e}"


@tool
def get_timeline(session_id: str) -> str:
    """Recall the full incident timeline for a session (oldest first).

    Args:
        session_id: the incident/chat session id.
    """
    try:
        resp = _table().query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key("session_id").eq(session_id),
            ScanIndexForward=True,
            Limit=50,
        )
    except Exception as e:  # noqa: BLE001
        return f"failed to read timeline: {e}"
    items = resp.get("Items", [])
    if not items:
        return f"No prior timeline for session {session_id} (new incident)."
    lines = [f"  [{it.get('step','?')}] {it.get('detail','')}" for it in items]
    return f"INCIDENT TIMELINE ({session_id}):\n" + "\n".join(lines)


MEMORY_TOOLS = [record_finding, get_timeline]
