"""M2 — Operational tools: let the agent SEE and ACT, not just talk.

Tools:
  run_smoke_test(service)   - hit the live API Gateway endpoint, report status   [read]
  get_logs(service, minutes)- pull recent CloudWatch error lines for the service [read]
  kb_search(query)          - retrieve matching post-mortems from the KB (M4)    [read]
  run_sql(statement)        - run a SQL statement (agent composes the real DDL)   [WRITE]
  redeploy_service(service) - redeploy a service's canonical build                [WRITE]

Configuration comes from environment variables (set by the IncidentCopilot stack):
  COFFEE_CUSTOMER_API, COFFEE_EMPLOYEE_API   - API Gateway base URLs
  COFFEE_CUSTOMER_FN,  COFFEE_EMPLOYEE_FN    - Lambda function names
  INJECTOR_FN                                - in-VPC SQL helper function name
  CODE_BUCKET, CUSTOMER_CLEAN_KEY, EMPLOYEE_CLEAN_KEY - clean zips for redeploy
  KB_ID                                      - Bedrock Knowledge Base id
  AWS_REGION                                 - provided by Lambda runtime
"""
import json
import os
import urllib.request
import urllib.error

import boto3
from strands import tool

REGION = os.environ.get("AWS_REGION", "ap-northeast-2")

_logs = boto3.client("logs", region_name=REGION)
_lambda = boto3.client("lambda", region_name=REGION)
_kb = boto3.client("bedrock-agent-runtime", region_name=REGION)

ERROR_SIGNATURES = [
    "Out of range value",
    "Duplicate entry",
    "Task timed out",
    "ENOSPC",
    "ER_TRUNCATED_WRONG_VALUE",
    "ETIMEDOUT",
    "PROTOCOL_CONNECTION_LOST",
    "error",
    "Error",
]

_API = {
    "customer": os.environ.get("COFFEE_CUSTOMER_API", ""),
    "employee": os.environ.get("COFFEE_EMPLOYEE_API", ""),
}
_FN = {
    "customer": os.environ.get("COFFEE_CUSTOMER_FN", "coffee-customer"),
    "employee": os.environ.get("COFFEE_EMPLOYEE_FN", "coffee-employee"),
}
_CLEAN_KEY = {
    "customer": os.environ.get("CUSTOMER_CLEAN_KEY", "lambda/customer.zip"),
    "employee": os.environ.get("EMPLOYEE_CLEAN_KEY", "lambda/employee.zip"),
}


@tool
def run_smoke_test(service: str) -> str:
    """Call the live endpoint of a coffee service and report whether it is healthy.

    Args:
        service: "customer" or "employee".
    """
    base = _API.get(service)
    if not base:
        return f"No API URL configured for service '{service}'."
    url = base.rstrip("/") + "/api/v1/supplier-list"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=25) as r:
            body = r.read(1000).decode("utf-8", "replace")
            return f"SMOKE {service} GET {url} -> HTTP {r.status}\nbody: {body}"
    except urllib.error.HTTPError as e:
        body = e.read(1000).decode("utf-8", "replace")
        return f"SMOKE {service} GET {url} -> HTTP {e.code} (FAIL)\nbody: {body}"
    except Exception as e:  # noqa: BLE001
        return f"SMOKE {service} GET {url} -> ERROR {type(e).__name__}: {e}"


@tool
def get_logs(service: str, minutes: int = 15) -> str:
    """Fetch recent error log lines for a coffee service from CloudWatch Logs.

    Args:
        service: "customer" or "employee".
        minutes: how far back to look (default 15).
    """
    fn = _FN.get(service)
    if not fn:
        return f"Unknown service '{service}'."
    group = f"/aws/lambda/{fn}"
    start = (int(__import__("time").time()) - minutes * 60) * 1000
    pattern = " ".join(f'?"{s}"' for s in ERROR_SIGNATURES)  # OR match on signatures
    try:
        resp = _logs.filter_log_events(
            logGroupName=group, startTime=start, filterPattern=pattern, limit=60
        )
    except _logs.exceptions.ResourceNotFoundException:
        return f"Log group {group} not found (service may never have run)."
    events = resp.get("events", [])
    if not events:
        return f"No matching error lines in {group} over the last {minutes}m."
    lines = [f"  {e['message'].strip()}" for e in events[-40:]]
    return f"LOGS {group} (last {minutes}m, {len(events)} matches):\n" + "\n".join(lines)


@tool
def kb_search(query: str) -> str:
    """Search the post-mortem knowledge base for incidents matching a failure
    MECHANISM. Returns excerpts with company + source URL for citation.

    Args:
        query: a mechanism-focused query, e.g. "integer primary key overflow INT32".
    """
    kb_id = os.environ.get("KB_ID")
    if not kb_id:
        return "KB_ID not configured."
    resp = _kb.retrieve(
        knowledgeBaseId=kb_id,
        retrievalQuery={"text": query},
        retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": 4}},
    )
    out = []
    for i, r in enumerate(resp.get("retrievalResults", []), 1):
        text = r.get("content", {}).get("text", "")[:700]
        md = r.get("metadata", {}) or {}
        company = md.get("company", "?")
        src = md.get("source_url", r.get("location", {}).get("s3Location", {}).get("uri", "?"))
        out.append(f"[{i}] {company} — {src}\n{text}")
    return "KB RESULTS:\n" + "\n\n".join(out) if out else "KB returned no relevant results."


@tool
def run_sql(statement: str) -> str:
    """대상 시스템의 MySQL DB에 SQL 문 하나를 실행합니다. 스키마 점검
    (예: SHOW CREATE TABLE ...)이나, 진단으로 도출한 실제 복구 DDL(예: 컬럼 타입
    변경)을 **직접 작성**해 실행하세요. 상태를 바꾸는 문장은 운영자의 명시적
    승인 후에만 실행합니다.

    Args:
        statement: 실행할 단일 SQL 문.
    """
    injector = os.environ.get("INJECTOR_FN", "coffee-fault-injector")
    r = _lambda.invoke(
        FunctionName=injector,
        Payload=json.dumps({"action": "run_sql", "sql": statement}).encode(),
    )
    return r["Payload"].read().decode("utf-8", "replace")


@tool
def redeploy_service(service: str) -> str:
    """해당 서비스의 Lambda를 정규(검증된) 빌드로 재배포합니다. 최근/현재 코드
    변경이 근본 원인일 때(잘못된 배포를 되돌릴 때) 사용합니다. 운영자의 명시적
    승인 후에만 실행합니다.

    Args:
        service: "customer" 또는 "employee".
    """
    bucket = os.environ.get("CODE_BUCKET")
    fn = _FN.get(service)
    if not fn:
        return f"unknown service '{service}'"
    if not bucket:
        return "CODE_BUCKET not configured."
    _lambda.update_function_code(FunctionName=fn, S3Bucket=bucket, S3Key=_CLEAN_KEY[service])
    _lambda.get_waiter("function_updated").wait(FunctionName=fn)
    return f"redeployed canonical build to {fn}"


OPERATIONAL_TOOLS = [run_smoke_test, get_logs, run_sql, redeploy_service]
# KB retrieval is a separate capability, enabled only at M4+.
KB_TOOLS = [kb_search]
