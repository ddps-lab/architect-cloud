# 수강생 실습 가이드 — SRE Incident Copilot

여러분은 **자기 AWS 환경**에서 SRE 인시던트 에이전트를 직접 만듭니다.
어려운 부품(IAM 역할·장애 주입기·라이브러리 레이어)은 CF로 한 번에 깔고,
**핵심(벡터 DB·지식베이스·에이전트 Lambda)** 은 콘솔에서 손으로 만듭니다.

리전은 모두 **ap-northeast-2 (서울)** 기준입니다. 실습은 **AWS CloudShell**에서
진행합니다(로컬 설치 불필요).

> 진행 중 나오는 출력값(ARN, 버킷명, KB ID 등)은 메모장에 적어두세요. 뒤에서 씁니다.

---

## 0. 사전 확인 + CloudShell 준비

확인할 것:
- 내 환경에 `coffee-serverless` 스택이 배포돼 있다 (대상 서비스 + RDS).
- Bedrock 모델 액세스가 켜져 있다 (사용 모델 + **Titan Text Embeddings v2**).
- 강사가 공유한 **채팅 사이트 URL** 을 받았다.

CloudShell 열기 (도구는 모두 사전 설치됨 — AWS CLI·Python3·Node·git·zip):
1. AWS 콘솔 오른쪽 위 **리전을 서울(ap-northeast-2)** 로 맞춘다.
2. 콘솔 상단 바의 **CloudShell 아이콘**(`>_`)을 클릭해 연다.
3. 저장소를 받고 작업 폴더로 이동한다:

```sh
git clone https://github.com/ddps-lab/architect-cloud.git
cd architect-cloud/agent_sre
```

> CloudShell은 자기 계정·리전 자격증명으로 자동 로그인돼 있어 별도 설정이 필요
> 없습니다. 홈 디렉터리는 세션이 끊겨도 유지되지만, 20분 이상 미사용 시 세션이
>재시작될 수 있습니다(그때는 다시 `cd architect-cloud/agent_sre`).

> **아직 `coffee-serverless` 가 없다면** 코드 버킷을 만들 필요 없이 바로 배포합니다.
> Lambda 코드(`coffee/customer.zip`·`coffee/employee.zip`)는 강사 공유 버킷
> (`samsung-cloud-architect`)에서 끌어옵니다(빌드 불필요):
> ```sh
> aws cloudformation deploy \
>   --template-file ../cloudformation/ServerlessApp_CF.yaml \
>   --stack-name coffee-serverless --capabilities CAPABILITY_IAM
> ```
> (강사 공유 버킷명이 다르면 `--parameter-overrides CodeBucket=<버킷명>` 추가)

---

## 1. 부품 배포 (CloudFormation, 1회, 콘솔)

장애 주입 Lambda(내 RDS 대상) + 에이전트 IAM 역할·관리형 정책 + 세션 버킷을
한 번에 만듭니다. VPC/RDS 배선(서브넷·SG·DB엔드포인트)은 `coffee-serverless`
스택의 Export 에서 **자동으로 가져오므로 입력할 값이 없습니다**. 코드(injector.zip)도
공유 버킷에서 직접 참조하므로 빌드/복사도 없습니다.

**콘솔에서:**
1. **CloudFormation 콘솔 → Create stack → With new resources**
2. Template source: **Amazon S3 URL** 선택 후 붙여넣기:
   `https://samsung-cloud-architect.s3.ap-northeast-2.amazonaws.com/cloudformation/AgentBase_CF.yaml`
3. Stack name: `agent-base`
4. Parameters: **그대로 둠** (전부 기본값 — coffee 스택명이 `coffee-serverless` 가
   아니면 `CoffeeStackName` 만 바꿉니다)
5. 다음 화면에서 **"I acknowledge that AWS CloudFormation might create IAM resources
   with custom names"** 체크 → Create stack
6. 생성 완료 후 **Outputs** 탭에서 다음을 메모하세요:
   - `AgentRoleArn` — 에이전트 Lambda 실행 역할
   - `LwaLayerArn` — Lambda Web Adapter 레이어
   - `SessionBucketName` — env `SESSION_BUCKET`
   - `InjectorFunctionName` — env `INJECTOR_FN` (보통 `coffee-fault-injector`)

> CLI 가 편하면 대신 `./infra/deploy_labbase.sh` 한 줄로도 됩니다(같은 결과).

---

## 1-B. 의존성 레이어 만들기 (콘솔, 직접)

라이브러리(Strands/fastapi/uvicorn/mcp/awslabs...)는 강사가 미리 빌드해 공유
버킷에 올려뒀습니다. 여러분은 그 S3 링크로 **레이어만 직접 생성**합니다(빌드 없음).

1. **Lambda 콘솔 → Layers → Create layer**
2. Name: `copilot-deps`
3. **Upload a file from Amazon S3** 선택 → S3 링크 URL 붙여넣기:
   `https://samsung-cloud-architect.s3.ap-northeast-2.amazonaws.com/copilot/layer.zip`
4. Compatible runtimes: **Python 3.14**
5. Create → 만들어진 **레이어 버전 ARN(`DepsLayerArn`)** 을 메모(4-4에서 사용)

---

## 2. S3 Vectors 벡터 버킷 + 인덱스 만들기 (직접)

```sh
./kb/setup_s3vectors.sh
```
출력된 **VectorBucketArn**, **VectorIndexArn** 을 메모합니다.
(차원 1024 / cosine — Titan Text Embeddings v2 에 맞춤)

---

## 3. Knowledge Base 만들기 + 회고 20건 적재 (직접)

### 3-1. KB 데이터 버킷에 문서 올리기
```sh
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
KB_BUCKET=copilot-kb-data-$ACCOUNT-ap-northeast-2
aws s3 mb s3://$KB_BUCKET --region ap-northeast-2 2>/dev/null || true
aws s3 cp kb/data "s3://$KB_BUCKET/danluu/" --recursive   # 20건(.txt + .metadata.json)
```

### 3-2. Bedrock 콘솔에서 Knowledge Base 생성
1. **Bedrock 콘솔 → Knowledge Bases → Create**
2. 데이터 소스: **S3** → `s3://<KB_BUCKET>/danluu/`
3. 임베딩 모델: **Titan Text Embeddings v2**
4. 벡터 스토어: **S3 Vectors** → 2번에서 만든 **Vector bucket / index** 선택
5. 생성 후 데이터 소스 **Sync** 실행 → 20건 인덱싱
6. **Knowledge base ID** 를 메모 (env `KB_ID`)

> CLI 선호 시: `kb/ingest_danluu.py sync --bucket <KB_BUCKET> --kb-id <KB_ID> --ds-id <DS_ID>`
> (KB/데이터소스를 먼저 만든 뒤 동기화)

---

## 4. 에이전트 Lambda 만들기 (콘솔, 직접)

### 4-1. 함수 코드 (공유 버킷에 발행됨 — 빌드·다운로드 불필요)
에이전트 함수 코드는 강사가 공유 버킷에 올려둡니다. 아래 S3 링크 URL 을 4-2 에서 사용합니다:
`https://samsung-cloud-architect.s3.ap-northeast-2.amazonaws.com/copilot/function.zip`

### 4-2. 함수 생성
- **Lambda 콘솔 → Create function → Author from scratch**
- Name: `strands-incident-copilot`, Runtime: **Python 3.14**, Arch: **x86_64**
- **Change default execution role → Use an existing role →** `AgentRoleArn`(1번)
- Create → **Code → Upload from → Amazon S3 location** → 위 `copilot/function.zip` S3 링크 붙여넣기
  (버킷·함수 모두 `ap-northeast-2` 라 S3 로딩 가능)

### 4-3. 핸들러·리소스 (Configuration)
- **Handler**: `lambda_src/run.sh`
- **Timeout**: 5 min, **Memory**: 1024 MB

### 4-4. 레이어 추가 (Code 탭 → Layers → Add a layer → Specify an ARN)
- `LwaLayerArn` (Lambda Web Adapter, 1번 출력)
- `DepsLayerArn` (의존성, 1-B에서 직접 만든 레이어)

### 4-5. 환경변수 (Configuration → Environment variables)

배포마다 달라지는 값만 넣습니다. 나머지(서비스 함수명·정리 키·injector·코드버킷·
세션버킷)는 코드에 박혀 있어 설정할 필요가 없습니다.

| Key | Value |
|-----|-------|
| `AWS_LAMBDA_EXEC_WRAPPER` | `/opt/bootstrap` (LWA) |
| `AWS_LWA_INVOKE_MODE` | `response_stream` (LWA) |
| `KB_ID` | (3번에서 메모한 Knowledge base ID, 모듈 4부터) |
| `COFFEE_CUSTOMER_API` | coffee-serverless 출력 `CustomerApiUrl` |
| `COFFEE_EMPLOYEE_API` | coffee-serverless 출력 `EmployeeApiUrl` |

> 모델 기본값은 `global.anthropic.claude-sonnet-4-6` 입니다(코드 내장). 다른 모델을
> 쓰려면 `MODEL_ID` 만 추가하세요.
> 선택: 모델 호출을 다른 리전으로 보내려면 `BEDROCK_REGION`, 세션 버킷을 기본
> (`copilot-sessions-<account>-<region>`)이 아닌 것으로 쓰려면 `SESSION_BUCKET` 만 추가.

> coffee API 주소: `aws cloudformation describe-stacks --stack-name coffee-serverless
> --query "Stacks[0].Outputs"` 에서 확인.

### 4-6. Function URL (Configuration → Function URL → Create)
- Auth type: **NONE**, Invoke mode: **RESPONSE_STREAM**, CORS: origin/methods/headers `*`
- 퍼블릭 권한 2개 추가(콘솔에서 자동 안 되면 CLI):
```sh
FN=strands-incident-copilot
aws lambda add-permission --function-name $FN --statement-id PublicUrl \
  --action lambda:InvokeFunctionUrl --principal "*" --function-url-auth-type NONE
aws lambda add-permission --function-name $FN --statement-id PublicInvoke \
  --action lambda:InvokeFunction --principal "*"
```
- 생성된 **Function URL** 을 메모.

### 4-7. 동작 확인
```sh
curl -s <FunctionURL>            # {"ok":true}
```

---

## 5. 채팅 연결
1. 강사가 공유한 **채팅 사이트** 열기
2. ⚙︎ 설정 → 내 **Function URL** 붙여넣고 저장

---

## 6. 장애 주입 + 모듈 실습

```sh
./faults/inject.sh f1     # 정수 PK 오버플로 (그 외 f2/f3/f4)
```

채팅에서 "employee 서비스가 이상해. 조사해줘." 라고 물어봅니다. 그다음 Lambda
콘솔 → 함수 → **Code → `lambda_src/agent_app.py`** 를 열고 모듈 줄의 `#` 을 지워
**Deploy** 한 뒤, 같은 질문으로 차이를 확인합니다.

| 모듈 | `agent_app.py` 에서 주석 해제할 줄 | 효과 |
|------|-----------------------------------|------|
| 1 골격 | (기본) | 도구 없어 증거를 요청하고 멈춤 |
| 2 도구 | `tools=m2_tools.ALL,` | 실제 로그·스모크·복구 도구 사용 |
| 3 기억 | `session_manager=m3_memory.memory(session_id),` | 이전 대화를 기억 |
| 4 지식베이스 | `tools=m2_tools.ALL + [m4_knowledge_base.search],` | 회고를 회사명·URL로 인용 |
| 5 AWS 문서 | `tools=m2_tools.ALL + [m4_knowledge_base.search] + m5_aws_docs.load(),` | AWS 공식문서 인용 |

복구는 채팅에서 **"적용해"** 라고 명시 승인할 때만 실행됩니다. 끝나면 원복:
```sh
./faults/restore.sh
```

---

## 7. 정리(삭제)

```sh
# 에이전트 Lambda / Function URL : 콘솔에서 삭제
# Knowledge Base / 데이터소스 : 콘솔에서 삭제
aws s3 rm s3://<KB_BUCKET> --recursive
aws s3vectors delete-index --vector-bucket-name <vec-bucket> --index-name postmortems
aws s3vectors delete-vector-bucket --vector-bucket-name <vec-bucket>
# AgentBase : 콘솔 CloudFormation 에서 agent-base 스택 삭제 (또는 CLI)
aws cloudformation delete-stack --stack-name agent-base
# coffee-serverless : 콘솔/CLI 로 스택 삭제 — 프론트엔드 버킷은 자동으로 비워짐
aws cloudformation delete-stack --stack-name coffee-serverless
```

> `coffee-serverless` 의 프론트엔드 버킷(`coffee-customer-*` / `coffee-employee-*`)은
> 스택에 포함된 자동 비우기 리소스가 삭제 시 비워주므로, 따로 `s3 rm` 할 필요가
> 없습니다. (KB/벡터 버킷은 직접 만든 것이라 위처럼 수동 정리)
