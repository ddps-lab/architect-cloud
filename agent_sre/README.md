# SRE Incident Copilot (실습)

danluu 회고 모음을 지식베이스로 삼아, 한 개의 AWS Strands 에이전트가 `coffee`
마이크로서비스의 장애를 **탐지 → 진단 → 복구 → 검증**하도록 만드는 실습입니다.
학생은 **`solution.py` 한 파일만** 수정하며, 모듈을 하나씩 켜 갑니다.

## 학생용: `lambda_src/agent_app.py` 한 파일을 Lambda 콘솔에서 편집

Lambda 콘솔 → `strands-incident-copilot` → 코드 탭에서 **`lambda_src/agent_app.py`**
를 열고, 모듈별로 **줄 앞의 `#`(주석)을 지워** 기능을 켭니다. [Deploy] 후 채팅
웹에서 같은 질문을 던져 차이를 확인하세요.

| 모듈 | 켜는 법 (`lambda_src/agent_app.py`) | 효과 |
|------|------------------------|------|
| 1 골격 | 기본 상태 (이미 켜짐) | 절차만 앎 → 도구 없어 증거를 요청하고 멈춤 |
| 2 도구 | `tools=tools.ALL` 주석 해제 | 실제 로그 조회·스모크·복구 도구 사용 |
| 3 기억 | `session_manager=memory(session_id)` 주석 해제 | 이전 대화를 기억(턴 넘어 회상) |
| 4 지식베이스 | `tools=tools.ALL + [knowledge_base.search]` | 실제 회고를 회사명·URL로 인용 |
| 5 AWS 문서 | `... + aws_docs.load()` | AWS 공식문서 MCP로 최신 정보 인용 |

서드파티 라이브러리(Strands·fastapi·mcp 등)는 Lambda **레이어**에 들어 있어 함수
코드에는 보이지 않습니다. 프로젝트 코드(`lambda_src/`)는 전부 함수 코드 안에
있어 콘솔에서 그대로 보고 편집할 수 있습니다(함수 코드 ~10KB, 인라인 편집 가능).

## 구조

```
agent_sre/
├── lambda_src/          함수 코드 (콘솔 편집 가능, 모든 프로젝트 .py)
│   ├── agent_app.py     🎓 학생이 편집하는 파일 (build_agent)
│   ├── runtime.py       FastAPI/SSE 서버 (agent_app.build_agent 호출)
│   ├── prompt.py        SYSTEM_PROMPT
│   ├── model.py         model() — Bedrock 모델
│   ├── tools.py         tools.ALL — smoke/logs/run_sql/redeploy
│   ├── knowledge_base.py knowledge_base.search — 회고 KB 검색
│   ├── aws_docs.py      aws_docs.load() — AWS 문서 MCP
│   └── memory.py        memory(session_id) — S3 세션 기억
├── run.sh               LWA 부팅 (uvicorn lambda_src.runtime:app)
├── faults/              장애 주입/복구 (inject.sh / restore.sh / injector Lambda)
├── kb/                  danluu 크롤러 + S3 Vectors 셋업
├── infra/               IncidentCopilot CloudFormation + package_and_deploy
└── web-chat/            채팅 SPA (스트리밍 + 도구 트레이스 + 마크다운)
```
> 서드파티 의존성은 `package_and_deploy.sh` 가 만든 Lambda 레이어(`copilot-deps`)에 있습니다.

## 사전 준비

- `coffee-serverless` 스택 배포됨(`../cloudformation/ServerlessApp_CF.yaml`).
- Bedrock 모델 액세스 활성화(ap-northeast-2). 기본 모델은 `MODEL_ID` 환경변수로 변경.
- 로컬: AWS CLI, Python 3.12, Node 18+, `zip`.

## 배포 (강사/최초 1회 + 학생이 solution.py 바꿀 때마다)

```sh
cd agent_sre

# (최초) 벡터스토어 + KB 적재
./kb/setup_s3vectors.sh
export VECTOR_BUCKET_ARN=...   VECTOR_INDEX_ARN=...   # 위 출력값
./infra/package_and_deploy.sh                 # incident-copilot 스택 + 코드
python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt
python kb/ingest_danluu.py crawl
python kb/ingest_danluu.py sync --bucket <KbDataBucket> --kb-id <KB_ID> --ds-id <DS_ID>
./web-chat/deploy_chat.sh

# (이후) solution.py 를 고친 뒤 다시 배포하려면:
./infra/package_and_deploy.sh
```

배포가 끝나면 출력된 **ChatSiteUrl**을 열고, ⚙︎설정에 **AgentFunctionUrl**을
붙여넣어 저장한 뒤 대화합니다.

> 모델 교체: `aws lambda update-function-configuration --function-name
> strands-incident-copilot --environment '{"Variables":{...,"MODEL_ID":"..."}}'`
> (inference profile 필요. 예: `global.anthropic.claude-sonnet-4-6`)

## 인시던트 실습 루프

```sh
# 장애 주입 (Appendix A — 실제 회고 메커니즘 재현)
./faults/inject.sh f1      # 정수 PK 오버플로 (Strava/Basecamp/GitHub)
# ./faults/inject.sh f2    # 커넥션 풀 고갈 (incident.io)
# ./faults/inject.sh f3    # 무한 로컬 로그 → ENOSPC (Tarsnap)
# ./faults/inject.sh f4    # 컬럼 타입 변경 (CircleCI)

# 채팅에서: "employee 서비스가 이상해. 조사해줘."
#   -> (모듈에 따라) 로그 진단 → 회고 인용 → 복구 제안. "적용해" 라고 하면 적용 후 검증.

./faults/restore.sh        # 끝나면 원상복구
```

## 장애 ↔ 실제 사건 (Appendix A)

| 장애 | 시그니처 | 실제 사건 | 복구 |
|------|----------|-----------|------|
| F1 | `Duplicate entry '2147483647'` / `Out of range value for 'id'` | Strava/Basecamp/GitHub | `id` → BIGINT |
| F2 | 부하 시 `Task timed out` | incident.io | 불필요 트랜잭션 제거·풀 상향 |
| F3 | `ENOSPC: no space left on device` | Tarsnap | 로컬 /tmp 로깅 제거 |
| F4 | `ER_TRUNCATED_WRONG_VALUE` | CircleCI 2021-11 | 관대한 읽기 + 백필 |

## 안전 & 정리

- 복구 도구(`run_sql`/`redeploy_service`)는 라이브 RDS/Lambda를 바꿉니다 —
  에이전트는 채팅에서 사람이 명시 승인할 때만 적용합니다.
- 장애 주입은 라이브 코드/스키마를 바꿉니다 — **실습 브랜치 전용**, 끝나면 `restore.sh`.
- 비용: Bedrock·S3 Vectors·CloudFront·Lambda. 정리:
  ```sh
  aws s3 rm s3://<ChatBucket> --recursive
  aws cloudformation delete-stack --stack-name incident-copilot
  aws s3vectors delete-index --vector-bucket-name <bucket> --index-name postmortems
  aws s3vectors delete-vector-bucket --vector-bucket-name <bucket>
  ```
