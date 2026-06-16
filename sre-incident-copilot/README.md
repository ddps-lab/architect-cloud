# SRE Incident Copilot

A single AWS Strands agent that **detects → diagnoses → recovers → verifies** real
incidents seeded into the `coffee` microservices, learning the 8 Strands modules
along the way. Diagnosis is grounded in the [danluu/post-mortems](https://github.com/danluu/post-mortems)
collection (Bedrock Knowledge Base over S3 Vectors), so the agent cites the real
incident whose **mechanism** matches the live failure and applies that incident's
actual remediation.

> Target system: the already-deployed `coffee-serverless` stack
> (API Gateway → Lambda `coffee-customer`/`coffee-employee` → RDS MySQL).

## Architecture

```
 user ─► CloudFront ─► S3 (chat SPA)   ── save agent API URL, chat ──┐
                                                                     ▼
              ┌──────────────► HTTP API ─► Agent Lambda (Strands, VPC) ─┬─► Bedrock (Claude Sonnet 4.6)
              │                                                         ├─► Bedrock KB (danluu, S3 Vectors)
   alarms/peers┘                                                        ├─► AWS Docs MCP (M5, local)
                                                                        ├─► tools: get_logs / run_smoke_test
                                                                        │          kb_search / apply_recovery
                                                                        ├─► DynamoDB incident timeline (memory)
                                                                        └─► fault-injector Lambda (VPC, SQL)
                                                                                   │
   coffee-customer / coffee-employee (VPC) ──────────────────────────► RDS MySQL (COFFEE)
```

## Layout

| Path | What |
|------|------|
| `agent/` | Strands agent: `system_prompt` (M1), `tools_operational` (M2), `memory` (M3), `mcp_setup` (M5), `agent`, `handler` (M6) |
| `kb/` | `ingest_danluu.py` (crawl post-mortems → S3 → KB), `setup_s3vectors.sh` |
| `faults/` | `inject.sh` / `restore.sh`, `injector_lambda/` (in-VPC SQL), `broken/` (F2/F3 variants) |
| `infra/` | `IncidentCopilot_CF.yaml`, `package_and_deploy.sh` |
| `web-chat/` | chat SPA + `deploy_chat.sh` |
| `steps/` | `run_local.py` — module before/after demos |

## Prerequisites

- `coffee-serverless` stack deployed (see `../cloudformation/ServerlessApp_CF.yaml`).
- Bedrock model access enabled in `ap-northeast-2` for **Claude Sonnet 4.6** and
  **Titan Text Embeddings v2** (Bedrock console → Model access).
- Local: AWS CLI, Python 3.12, Node 18+, `zip`. For M5 MCP: `uv`/`uvx`.

## Deploy (ordered)

```sh
cd sre-incident-copilot

# 1) Vector store
./kb/setup_s3vectors.sh
export VECTOR_BUCKET_ARN=...   # printed above
export VECTOR_INDEX_ARN=...

# 2) Agent + injector + KB + API + chat infra
./infra/package_and_deploy.sh                 # deploys the "incident-copilot" stack

# 3) Knowledge base content (crawl danluu originals, then ingest)
python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
python kb/ingest_danluu.py crawl              # writes kb/data/
KB=$(aws cloudformation describe-stacks --stack-name incident-copilot \
      --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseId'].OutputValue" --output text)
DS=$(aws cloudformation describe-stacks --stack-name incident-copilot \
      --query "Stacks[0].Outputs[?OutputKey=='DataSourceId'].OutputValue" --output text)
BK=$(aws cloudformation describe-stacks --stack-name incident-copilot \
      --query "Stacks[0].Outputs[?OutputKey=='KbDataBucketName'].OutputValue" --output text)
python kb/ingest_danluu.py sync --bucket "$BK" --kb-id "$KB" --ds-id "$DS"

# 4) Chat web
./web-chat/deploy_chat.sh
```

Then open the printed **ChatSiteUrl**, click ⚙︎ 설정, paste the **AgentFunctionUrl**
(the Lambda Function URL — it has no 30s API Gateway cap, needed for multi-step
agent runs), save, and chat.

> The agent runs several tool calls + model rounds per turn (often >30s), so the
> chat path uses the Lambda Function URL rather than API Gateway. Public Function
> URLs in this account require BOTH `lambda:InvokeFunctionUrl` and
> `lambda:InvokeFunction` granted to `*` (both are in the template).

## Run an incident (lab loop)

```sh
# Seed a fault (Appendix A) into the live coffee services
./faults/inject.sh f1        # integer PK overflow (Strava/Basecamp/GitHub)
# ./faults/inject.sh f2      # pool exhaustion (incident.io)
# ./faults/inject.sh f3      # unbounded /tmp logging -> ENOSPC (Tarsnap)
# ./faults/inject.sh f4      # column type change (CircleCI)

# In the chat UI:  "customer/employee 서비스가 이상해. 조사해줘."
#   -> agent runs smoke test, pulls logs, cites the matching post-mortem,
#      proposes the fix. Tell it "적용해" to apply (apply_recovery), then it verifies.

# Restore everything to healthy when done
./faults/restore.sh
```

## Module before/after (what each Strands capability buys)

| Module | Before | After |
|--------|--------|-------|
| M1 skeleton | guesses a cause | follows detect→diagnose→recover→verify, asks for evidence |
| M2 tools | can't see logs | pulls real logs, runs smoke tests |
| M3 memory | forgets earlier findings | recalls the incident timeline (DynamoDB) |
| M4 KB RAG | generic advice / hallucination | cites the real incident (company + URL) + its remediation |
| M5 MCP (AWS Docs) | stale/hallucinated post-cutoff AWS info | current docs + source URLs |
| M6 API + web | runs only on a laptop | team/alarms call it; chat web UI |

Try the before/after locally with `steps/run_local.py --module m1|m2|m3|m4|m5`.

## Faults ↔ real incidents (Appendix A)

| Fault | Signature | Real incident | Fix |
|-------|-----------|---------------|-----|
| F1 | `Out of range value for column 'id'` / `Duplicate entry '2147483647'` | Strava/Basecamp/GitHub | `id` → BIGINT |
| F2 | `Task timed out` under load | incident.io | drop per-request txn, cache table check, raise pool |
| F3 | `ENOSPC: no space left on device` | Tarsnap | remove local /tmp logging |
| F4 | `ER_TRUNCATED_WRONG_VALUE` | CircleCI 2021-11 | lenient read + backfill |

## Safety & cleanup

- `apply_recovery` changes live RDS/Lambda. With the approval gate removed, the
  **human operator is the gate**: the agent only applies a fix when you tell it to in chat.
- Fault-injection edits live code/schema — **lab branch only, never merge to prod**.
  Always run `faults/restore.sh` afterward.
- Costs: Bedrock calls, S3 Vectors, CloudFront, DynamoDB, Lambda. Tear down:

```sh
aws s3 rm s3://$(aws cloudformation describe-stacks --stack-name incident-copilot \
  --query "Stacks[0].Outputs[?OutputKey=='ChatBucketName'].OutputValue" --output text) --recursive
aws cloudformation delete-stack --stack-name incident-copilot
# delete the S3 Vectors index + bucket
aws s3vectors delete-index  --vector-bucket-name <bucket> --index-name postmortems
aws s3vectors delete-vector-bucket --vector-bucket-name <bucket>
```

## M8 — wrap-up

After one end-to-end run, write a one-line danluu-style retro: **"[cause]. [fix]."**
