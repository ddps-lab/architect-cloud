"""M2 — Operational tools: let the agent SEE and ACT, not just talk.

Tools:
  run_smoke_test(service)   - hit the live API Gateway endpoint, report status   [read]
  get_logs(service, minutes)- pull recent CloudWatch error lines for the service [read]
  kb_search(query)          - retrieve matching post-mortems from the KB (M4)    [read]
  apply_recovery(action)    - perform the real fix (RDS ALTER / clean redeploy)  [WRITE]

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
def apply_recovery(action: str) -> str:
    """Apply a state-changing remediation. ONLY call after the human operator
    explicitly approves in chat. Re-run a smoke test afterward to verify.

    Args:
        action: one of
            "fix_f1" - migrate suppliers.id to BIGINT (integer PK overflow)
            "fix_f2" - redeploy clean code (remove pool-exhausting transactions)
            "fix_f3" - redeploy clean code (remove unbounded /tmp logging)
            "fix_f4" - restore phone column to VARCHAR
    """
    injector = os.environ.get("INJECTOR_FN", "coffee-fault-injector")

    def call_injector(injector_action):
        r = _lambda.invoke(
            FunctionName=injector,
            Payload=json.dumps({"action": injector_action}).encode(),
        )
        return r["Payload"].read().decode("utf-8", "replace")

    def redeploy_clean(service):
        bucket = os.environ.get("CODE_BUCKET")
        if not bucket:
            return "CODE_BUCKET not configured; cannot redeploy."
        _lambda.update_function_code(
            FunctionName=_FN[service], S3Bucket=bucket, S3Key=_CLEAN_KEY[service]
        )
        _lambda.get_waiter("function_updated").wait(FunctionName=_FN[service])
        return f"redeployed clean code to {_FN[service]}"

    if action == "fix_f1":
        return "fix_f1 applied: " + call_injector("restore_id_bigint")
    if action == "fix_f4":
        return "fix_f4 applied: " + call_injector("restore_phone_varchar")
    if action == "fix_f2":
        return "fix_f2 applied: " + redeploy_clean("customer") + "; " + redeploy_clean("employee")
    if action == "fix_f3":
        return "fix_f3 applied: " + redeploy_clean("customer") + "; " + redeploy_clean("employee")
    return f"Unknown recovery action '{action}'. Known: fix_f1, fix_f2, fix_f3, fix_f4."


OPERATIONAL_TOOLS = [run_smoke_test, get_logs, kb_search, apply_recovery]
