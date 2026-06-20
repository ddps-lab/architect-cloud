# SRE Incident Copilot (실습)

danluu 회고 모음을 지식베이스로 삼아, **하나의 AWS Strands 에이전트**가 `coffee`
마이크로서비스의 장애를 **탐지 → 진단 → 복구 → 검증** 하도록 직접 만들어 보는
실습입니다. 수강생은 에이전트 Lambda에서 **모듈을 한 줄씩 주석 해제**하며 능력을
하나씩 붙입니다(골격 → 도구 → 기억 → 지식베이스 → AWS 문서 MCP).

> 어려운 배선(서버·스트리밍·도구 구현·라이브러리)은 `lambda_src` 패키지와 레이어에
> 숨겨져 있고, 수강생은 `lambda_src/agent_app.py` 의 `build_agent` 만 편집합니다.

## 📖 문서
- **수강생**: [`docs/STUDENT_GUIDE.md`](docs/STUDENT_GUIDE.md) — 처음부터 끝까지 단계별
- **강사**: [`docs/INSTRUCTOR_SETUP.md`](docs/INSTRUCTOR_SETUP.md) — 사전 1회 준비

## 아키텍처

```
   수강생 ─► (공유) 채팅 웹 ─► 내 에이전트 Lambda(Strands, LWA 스트리밍)
                                   ├─► Bedrock (LLM)
                                   ├─► Knowledge Base (danluu 회고 20건 / S3 Vectors)
                                   ├─► AWS Docs MCP (모듈 5)
                                   ├─► 도구: get_logs / run_smoke_test / run_sql / redeploy
                                   ├─► S3 세션 기억 (모듈 3)
                                   └─► 장애 주입 Lambda ─► RDS(MySQL)
   coffee-customer / employee (대상 서비스) ───────────────► RDS
```

## 책임 분담

| 구분 | 누가 | 방법 |
|------|------|------|
| 공유 산출물(injector.zip·layer.zip) | 강사 (전역 1회) | `infra/publish_artifacts.sh` → `samsung-cloud-architect` |
| 공유 채팅 웹 | 강사 (전역 1회) | `web-chat/deploy_chat.sh` |
| coffee-serverless (대상+RDS) | 수강생 (각자) | `../cloudformation/ServerlessApp_CF.yaml` |
| LabBase: 장애주입·IAM 역할·세션버킷 | 수강생 (각자, CF 1회) | `infra/deploy_labbase.sh` |
| **의존성 레이어** | **수강생 (직접, 콘솔)** | 공유 버킷 layer.zip S3 링크로 생성 |
| **S3 Vectors · Knowledge Base · 적재** | **수강생 (직접)** | 핵심 실습 |
| **에이전트 Lambda 생성·편집** | **수강생 (직접, 콘솔)** | 핵심 실습 |
| 장애 주입 | 수강생 (각자) | `faults/inject.sh` (자기 RDS) |

## 구조

```
agent_sre/
├── lambda_src/          에이전트 함수 코드 (콘솔 편집 가능, 모든 프로젝트 .py)
│   ├── agent_app.py     🎓 수강생이 편집 (build_agent — 모듈 주석 해제)
│   ├── runtime.py       FastAPI/SSE 서버 (agent_app.build_agent 호출)
│   ├── run.sh           LWA 부팅 (Handler=lambda_src/run.sh)
│   ├── m1_prompt.py m1_model.py m2_tools.py m3_memory.py
│   └── m4_knowledge_base.py m5_aws_docs.py
├── infra/
│   ├── publish_artifacts.sh injector.zip·layer.zip·coffee zip 빌드→공유버킷 (강사 1회)
│   ├── deploy_labbase.sh    AgentBase 스택 배포 (수강생, CLI 선택지)
│   └── build_function_zip.sh  function.zip(lambda_src) 생성
├── kb/                  setup_s3vectors.sh, ingest_danluu.py, data/(회고 20건)
├── faults/              inject.sh / restore.sh / injector_lambda/
├── web-chat/            공유 채팅 SPA + ChatWeb_CF.yaml + deploy_chat.sh
└── docs/                STUDENT_GUIDE.md, INSTRUCTOR_SETUP.md

../cloudformation/
├── ServerlessApp_CF.yaml   coffee 대상 서비스(VPC+RDS+Lambda+APIGW+S3+CF)
└── AgentBase_CF.yaml       injector(공유버킷 참조)·IAM역할·세션버킷 (수강생 1회)
```

## 장애 ↔ 실제 회고 (지식베이스 20건이 이 메커니즘들에 대응)

| 장애 | 시그니처 | 대표 회고 | 복구 |
|------|----------|-----------|------|
| F1 | `Duplicate entry '2147483647'` / `Out of range value for 'id'` | GitHub(INT32→BIGINT), Heroku FK 오버플로, Ariane 5 | `id` → BIGINT |
| F2 | 부하 시 `Task timed out` | incident.io (커넥션 풀 고갈) | 불필요 트랜잭션 제거·풀 상향 |
| F3 | `ENOSPC: no space left on device` | Tarsnap (무한 로컬 로그) | 로컬 로깅 제거 |
| F4 | `ER_TRUNCATED_WRONG_VALUE` | CircleCI (컬럼 타입 변경) | 관대한 읽기 + 백필 |

## 모델
`MODEL_ID` 환경변수로 지정(추론 프로파일). 예: `global.anthropic.claude-sonnet-4-6`,
`apac.amazon.nova-micro-v1:0`. on-demand 미지원 모델은 inference profile ID가
필요하고, Bedrock 모델 액세스가 켜져 있어야 합니다.

## 안전
- 복구 도구(`run_sql`/`redeploy_service`)는 라이브 RDS/Lambda를 바꿉니다 — 에이전트는
  채팅에서 사람이 **명시 승인**할 때만 적용합니다.
- 장애 주입은 라이브 코드/스키마를 바꿉니다 — 실습용이며 끝나면 `faults/restore.sh`.
- 정리(삭제) 절차는 `docs/STUDENT_GUIDE.md` 7장 참고.
