"""운영 도구 모음 (완성품). 학생은 solution.py 에서 `tools.ALL` 로 한 번에 붙입니다.

  run_smoke_test(service)    - 라이브 엔드포인트 상태 확인            [읽기]
  get_logs(service, minutes) - CloudWatch 최근 에러 로그 조회         [읽기]
  run_sql(statement)         - DB에 SQL 실행(복구 DDL을 직접 작성)    [쓰기]
  redeploy_service(service)  - 서비스 정규 빌드 재배포                [쓰기]

설정은 환경변수에서 옵니다(스택이 자동 주입). 학생이 손댈 필요 없음.
"""
import json
import os
import time
import urllib.request
import urllib.error

import boto3
from strands import tool

REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
_logs = boto3.client("logs", region_name=REGION)
_lambda = boto3.client("lambda", region_name=REGION)

ERROR_SIGNATURES = [
    "Out of range value", "Duplicate entry", "Task timed out", "ENOSPC",
    "ER_TRUNCATED_WRONG_VALUE", "ETIMEDOUT", "PROTOCOL_CONNECTION_LOST", "error", "Error",
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
    """coffee 서비스의 라이브 엔드포인트를 호출해 정상 여부를 확인합니다.

    Args:
        service: "customer" 또는 "employee".
    """
    base = _API.get(service)
    if not base:
        return f"No API URL configured for service '{service}'."
    url = base.rstrip("/") + "/api/v1/supplier-list"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method="GET"), timeout=25) as r:
            body = r.read(1000).decode("utf-8", "replace")
            return f"SMOKE {service} GET {url} -> HTTP {r.status}\nbody: {body}"
    except urllib.error.HTTPError as e:
        body = e.read(1000).decode("utf-8", "replace")
        return f"SMOKE {service} GET {url} -> HTTP {e.code} (FAIL)\nbody: {body}"
    except Exception as e:  # noqa: BLE001
        return f"SMOKE {service} GET {url} -> ERROR {type(e).__name__}: {e}"


@tool
def get_logs(service: str, minutes: int = 15) -> str:
    """coffee 서비스의 최근 에러 로그 라인을 CloudWatch에서 가져옵니다.

    Args:
        service: "customer" 또는 "employee".
        minutes: 조회 범위(분), 기본 15.
    """
    fn = _FN.get(service)
    if not fn:
        return f"Unknown service '{service}'."
    group = f"/aws/lambda/{fn}"
    start = (int(time.time()) - minutes * 60) * 1000
    pattern = " ".join(f'?"{s}"' for s in ERROR_SIGNATURES)
    try:
        resp = _logs.filter_log_events(logGroupName=group, startTime=start, filterPattern=pattern, limit=60)
    except _logs.exceptions.ResourceNotFoundException:
        return f"Log group {group} not found (service may never have run)."
    events = resp.get("events", [])
    if not events:
        return f"No matching error lines in {group} over the last {minutes}m."
    lines = [f"  {e['message'].strip()}" for e in events[-40:]]
    return f"LOGS {group} (last {minutes}m, {len(events)} matches):\n" + "\n".join(lines)


@tool
def run_sql(statement: str) -> str:
    """대상 MySQL DB에 SQL 문 하나를 실행합니다. 스키마 점검(SHOW CREATE TABLE ...)
    이나 진단으로 도출한 실제 복구 DDL을 직접 작성해 실행하세요. 상태를 바꾸는
    문장은 운영자의 명시적 승인 후에만 실행합니다.

    Args:
        statement: 실행할 단일 SQL 문.
    """
    injector = os.environ.get("INJECTOR_FN", "coffee-fault-injector")
    r = _lambda.invoke(FunctionName=injector, Payload=json.dumps({"action": "run_sql", "sql": statement}).encode())
    return r["Payload"].read().decode("utf-8", "replace")


@tool
def redeploy_service(service: str) -> str:
    """해당 서비스의 Lambda를 정규(검증된) 빌드로 재배포합니다. 최근/현재 코드
    변경이 근본 원인일 때 사용합니다. 운영자의 명시적 승인 후에만 실행합니다.

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


# 학생이 solution.py 에서 한 번에 붙이는 도구 목록.
ALL = [run_smoke_test, get_logs, run_sql, redeploy_service]
