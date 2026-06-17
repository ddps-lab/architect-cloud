# =============================================================================
#  SRE Incident Copilot — 에이전트 코드  (이 파일을 Lambda 콘솔에서 편집합니다)
# =============================================================================
#
#  이 파일이 곧 람다 함수 코드입니다. Lambda 콘솔의 코드 편집기에서 열어,
#  모듈을 하나씩 "줄 앞의 #(샵)을 지워" 켜고 [Deploy] 한 뒤 채팅으로 확인하세요.
#
#  어려운 부분(서버/도구/AWS 연결)은 같은 패키지 lambda_src 안에 들어 있습니다.
#  여러분은 아래 build_agent 안의 주석만 풀면 됩니다.
# =============================================================================

from strands import Agent
from lambda_src import tools, knowledge_base, aws_docs, memory, model, SYSTEM_PROMPT


def build_agent(session_id):
    """채팅 요청마다 호출되어 에이전트(조사관)를 만들어 줍니다."""

    agent = Agent(
        model=model(),                  # 사용할 LLM (바꿀 필요 없음)
        system_prompt=SYSTEM_PROMPT,    # ✅ 모듈 1: 조사 "절차"를 알려준다

        # ── 모듈 2: 도구 붙이기 ───────────────────────────────────────────
        #   아래 한 줄의 # 을 지우면 로그 조회·스모크테스트·복구 도구가 켜집니다.
        # tools=tools.ALL,

        # ── 모듈 4: 회고 지식베이스 검색 추가 ────────────────────────────
        #   위 "tools=tools.ALL," 줄을 지우고, 대신 아래 줄의 # 을 지우세요.
        # tools=tools.ALL + [knowledge_base.search],

        # ── 모듈 5: AWS 공식문서(MCP) 추가 ──────────────────────────────
        #   위 tools 줄을 지우고, 대신 아래 줄의 # 을 지우세요.
        # tools=tools.ALL + [knowledge_base.search] + aws_docs.load(),

        # ── 모듈 3: 기억(메모리) 붙이기 ─────────────────────────────────
        #   아래 한 줄의 # 을 지우면 이전 대화를 기억합니다.
        # session_manager=memory(session_id),
    )
    return agent
