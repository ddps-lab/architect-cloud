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

---

## 1. 부품 배포 (CF, 1회) — `deploy_labbase.sh`

장애 주입 Lambda(내 RDS 대상) + 에이전트 IAM 역할 + 세션 버킷 + 의존성 레이어를
한 번에 만듭니다.

```sh
cd agent_sre
./infra/deploy_labbase.sh
```

끝나면 출력 표에서 다음을 메모하세요:
- `AgentRoleArn` — 에이전트 Lambda 실행 역할
- `DepsLayerArn` — 의존성 레이어
- `LwaLayerArn` — Lambda Web Adapter 레이어
- `SessionBucketName` — env `SESSION_BUCKET`
- `InjectorFunctionName` — env `INJECTOR_FN` (보통 `coffee-fault-injector`)

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

### 4-1. 함수 코드 zip
```sh
./infra/build_function_zip.sh        # function.zip 생성 (lambda_src 만, 수십 KB)
```
CloudShell에서 만든 `function.zip` 을 콘솔에 올리려면 내 PC로 내려받습니다:
**CloudShell 우측 상단 Actions → Download file → `agent_sre/function.zip`**
(경로 입력 시 홈 기준 상대경로, 예: `architect-cloud/agent_sre/function.zip`)

### 4-2. 함수 생성
- **Lambda 콘솔 → Create function → Author from scratch**
- Name: `strands-incident-copilot`, Runtime: **Python 3.12**, Arch: **x86_64**
- **Change default execution role → Use an existing role →** `AgentRoleArn`(1번)
- Create → **Code → Upload from → .zip** → `function.zip`

### 4-3. 핸들러·리소스 (Configuration)
- **Handler**: `lambda_src/run.sh`
- **Timeout**: 5 min, **Memory**: 1024 MB

### 4-4. 레이어 추가 (Code 탭 → Layers → Add a layer → Specify an ARN)
- `LwaLayerArn` (Lambda Web Adapter)
- `DepsLayerArn` (의존성)

### 4-5. 환경변수 (Configuration → Environment variables)

| Key | Value |
|-----|-------|
| `AWS_LAMBDA_EXEC_WRAPPER` | `/opt/bootstrap` |
| `AWS_LWA_INVOKE_MODE` | `response_stream` |
| `PORT` | `8000` |
| `MODEL_ID` | `global.anthropic.claude-sonnet-4-6` (또는 사용 모델 추론 프로파일) |
| `BEDROCK_REGION` | `ap-northeast-2` |
| `KB_ID` | (3번에서 메모한 Knowledge base ID) |
| `SESSION_BUCKET` | (1번 `SessionBucketName`) |
| `INJECTOR_FN` | `coffee-fault-injector` |
| `COFFEE_CUSTOMER_API` | coffee-serverless 출력 `CustomerApiUrl` |
| `COFFEE_EMPLOYEE_API` | coffee-serverless 출력 `EmployeeApiUrl` |
| `COFFEE_CUSTOMER_FN` | `coffee-customer` |
| `COFFEE_EMPLOYEE_FN` | `coffee-employee` |
| `CODE_BUCKET` | `coffee-lambda-code-<account>-apne2` |
| `CUSTOMER_CLEAN_KEY` | `lambda/customer.zip` |
| `EMPLOYEE_CLEAN_KEY` | `lambda/employee.zip` |

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
| 2 도구 | `tools=tools.ALL,` | 실제 로그·스모크·복구 도구 사용 |
| 3 기억 | `session_manager=memory(session_id),` | 이전 대화를 기억 |
| 4 지식베이스 | `tools=tools.ALL + [knowledge_base.search],` | 회고를 회사명·URL로 인용 |
| 5 AWS 문서 | `tools=tools.ALL + [knowledge_base.search] + aws_docs.load(),` | AWS 공식문서 인용 |

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
aws cloudformation delete-stack --stack-name copilot-labbase
```
