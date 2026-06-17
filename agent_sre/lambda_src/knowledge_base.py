"""회고(post-mortem) 지식베이스 검색 도구 (완성품).

학생은 agent_app.py 에서 `knowledge_base.search` 를 도구 목록에 추가합니다.
실패 사례의 '메커니즘'으로 검색하면 일치하는 실제 사건을 회사명·URL과 함께
돌려줍니다.
"""
import os

import boto3
from strands import tool

REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
_kb = boto3.client("bedrock-agent-runtime", region_name=REGION)


@tool
def search(query: str) -> str:
    """회고 지식베이스에서 실패 '메커니즘'이 일치하는 사건을 검색합니다. 인용용
    회사명 + 출처 URL이 포함된 발췌를 반환합니다.

    Args:
        query: 메커니즘 중심 질의. 예: "integer primary key overflow INT32".
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
