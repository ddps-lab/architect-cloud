# =============================================================================
#  SRE Incident Copilot — 에이전트 코드  (이 파일을 Lambda 콘솔에서 편집합니다)
# =============================================================================
#
#  이 파일이 곧 람다 함수 코드입니다. Lambda 콘솔의 코드 편집기에서 열어,
#  모듈을 하나씩 "줄 앞의 #(샵)을 지워" 켜고 [Deploy] 한 뒤 채팅으로 확인하세요.
#
#  각 모듈은 같은 폴더의 파일과 1:1로 짝지어 있습니다(파일명 앞의 m1~m5):
#     m1_prompt.py / m1_model.py  · m2_tools.py · m3_memory.py
#     m4_knowledge_base.py · m5_aws_docs.py
#  어려운 부분은 그 파일들 안에 이미 완성돼 있습니다. 여러분은 아래 build_agent
#  안의 주석(#)만 풀면 됩니다.
# =============================================================================

from strands import Agent
from lambda_src import (
    m1_prompt,          # 모듈 1: 시스템 프롬프트(조사 절차)
    m1_model,           # 모듈 1: 사용할 LLM
    m2_tools,           # 모듈 2: 운영 도구 모음
    m3_memory,          # 모듈 3: 대화 기억
    m4_knowledge_base,  # 모듈 4: 회고 지식베이스 검색
    m5_aws_docs,        # 모듈 5: AWS 공식문서(MCP)
)


def build_agent(session_id):
    """채팅 요청마다 호출되어 에이전트(조사관)를 만들어 줍니다."""

    agent = Agent(
        model=m1_model.model(),                  # 사용할 LLM (바꿀 필요 없음)
        system_prompt=m1_prompt.SYSTEM_PROMPT,   # ✅ 모듈 1: 조사 "절차"를 알려준다

        # ── 모듈 2: 도구 붙이기 (m2_tools.py) ─────────────────────────────
        #   아래 한 줄의 # 을 지우면 로그 조회·스모크테스트·복구 도구가 켜집니다.
        # tools=m2_tools.ALL,

        # ── 모듈 3: 기억(메모리) 붙이기 (m3_memory.py) ──────────────────
        #   아래 한 줄의 # 을 지우면 이전 대화를 기억합니다.
        # session_manager=m3_memory.memory(session_id),

        # ── 모듈 4: 회고 지식베이스 검색 추가 (m4_knowledge_base.py) ──────
        #   위 "tools=m2_tools.ALL," 줄을 지우고, 대신 아래 줄의 # 을 지우세요.
        # tools=m2_tools.ALL + [m4_knowledge_base.search],

        # ── 모듈 5: AWS 공식문서(MCP) 추가 (m5_aws_docs.py) ──────────────
        #   위 tools 줄을 지우고, 대신 아래 줄의 # 을 지우세요.
        # tools=m2_tools.ALL + [m4_knowledge_base.search] + m5_aws_docs.load(),
    )
    return agent
