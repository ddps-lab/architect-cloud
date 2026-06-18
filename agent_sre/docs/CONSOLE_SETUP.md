# Lambda 콘솔에서 에이전트 함수 만들기

이 문서는 **AWS 콘솔에서 직접** SRE Incident Copilot 에이전트 Lambda를 만드는
방법입니다. (CloudFormation으로 한 번에 만들려면 `infra/package_and_deploy.sh`
를 쓰세요. 이 문서는 콘솔에서 손으로 만드는 학습/이해용입니다.)

리전은 모두 **ap-northeast-2 (서울)** 기준입니다.

---

## 0. 사전 준비 (이미 되어 있어야 하는 것)

- `coffee-serverless` 스택 배포됨 (대상 서비스 + RDS + API).
- 회고 지식베이스(KB) + S3 Vectors 생성·적재됨 (`kb/setup_s3vectors.sh`, `kb/ingest_danluu.py`).
- 코드 zip 2개가 S3에 업로드돼 있어야 합니다(아래 1번에서 만듭니다):
  - 함수 코드 zip: `lambda_src/` 폴더를 통째로 zip
  - 의존성 레이어 zip: 서드파티 라이브러리

> 가장 쉬운 길은 `./infra/package_and_deploy.sh` 를 한 번 실행해 레이어와 zip을
> S3(`coffee-lambda-code-<account>-apne2/copilot/...`)에 올려두는 것입니다. 그
> 다음 콘솔에서 함수만 손으로 구성해 보면 이해가 쉽습니다.

### 채워 넣을 값 미리 모으기 (CLI)
콘솔 환경변수에 넣을 값들입니다. 터미널에서 한 번에 뽑아두세요.

```sh
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
COFFEE=coffee-serverless ; COPILOT=incident-copilot

# coffee 서비스 정보
aws cloudformation describe-stacks --stack-name $COFFEE --region $REGION \
  --query "Stacks[0].Outputs[?OutputKey=='CustomerApiUrl'||OutputKey=='EmployeeApiUrl'].{K:OutputKey,V:OutputValue}" --output table

# KB / 세션 버킷 (copilot 스택이 이미 있으면)
aws cloudformation describe-stacks --stack-name $COPILOT --region $REGION \
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseId'].OutputValue" --output text   # -> KB_ID
echo "SESSION_BUCKET=copilot-sessions-$ACCOUNT-$REGION"
echo "CODE_BUCKET=coffee-lambda-code-$ACCOUNT-apne2"
```

레이어 ARN 2개도 필요합니다:
- **LWA(어댑터) 레이어**: `arn:aws:lambda:ap-northeast-2:753240598075:layer:LambdaAdapterLayerX86:28`
- **의존성 레이어**: `aws lambda list-layer-versions --layer-name copilot-deps --region ap-northeast-2 --query "LayerVersions[0].LayerVersionArn" --output text`

---

## 1. (필요 시) 의존성 레이어 만들기

이미 `copilot-deps` 레이어가 있으면 건너뜁니다. 없으면:

```sh
# 서드파티 라이브러리를 python/ 아래에 설치 후 zip
mkdir -p layer/python
python3 -m pip install -r requirements.txt -t layer/python \
  --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all:
rm -rf layer/python/boto3 layer/python/botocore   # 런타임 제공분 제거
(cd layer && zip -qr ../layer.zip .)

aws lambda publish-layer-version --layer-name copilot-deps --region ap-northeast-2 \
  --compatible-runtimes python3.12 --zip-file fileb://layer.zip \
  --query LayerVersionArn --output text
```
출력된 ARN을 적어둡니다.

---

## 2. 함수 코드 zip 만들기

`lambda_src/` 폴더만 압축합니다 (서드파티 라이브러리는 레이어에 있으므로 제외).

```sh
cd agent_sre
zip -qr function.zip lambda_src        # lambda_src/ 가 zip 루트에 들어가도록
```
> 이 zip은 수십 KB로 작아서 콘솔 인라인 편집이 가능합니다.

---

## 3. 콘솔에서 함수 생성

1. **Lambda 콘솔** → **Create function** → **Author from scratch**
2. 기본 정보
   - Function name: `strands-incident-copilot`
   - Runtime: **Python 3.12**
   - Architecture: **x86_64**
3. **Create function**
4. **Code** 탭 → **Upload from** → **.zip file** → 위 `function.zip` 업로드
   - (또는 작은 코드라 이후 콘솔 편집기에서 직접 수정 가능)

---

## 4. 핸들러 · 런타임 설정 (Configuration → General configuration / Runtime settings)

- **Handler**: `lambda_src/run.sh`
- **Timeout**: `5 min` (300초)
- **Memory**: `1024 MB`

---

## 5. 레이어 추가 (Code 탭 맨 아래 Layers → Add a layer)

순서 상관없이 둘 다 추가 (Specify an ARN):
1. `arn:aws:lambda:ap-northeast-2:753240598075:layer:LambdaAdapterLayerX86:28`  (LWA)
2. `…:layer:copilot-deps:<버전>`  (의존성)

---

## 6. 환경변수 (Configuration → Environment variables)

| Key | Value | 설명 |
|-----|-------|------|
| `AWS_LAMBDA_EXEC_WRAPPER` | `/opt/bootstrap` | LWA 부팅 |
| `AWS_LWA_INVOKE_MODE` | `response_stream` | 스트리밍 |
| `PORT` | `8000` | 내부 웹서버 포트 |
| `MODEL_ID` | `global.anthropic.claude-sonnet-4-6` | 사용 모델(추론 프로파일) |
| `BEDROCK_REGION` | `ap-northeast-2` | 모델 호출 리전 |
| `KB_ID` | `<KnowledgeBaseId>` | 회고 KB |
| `SESSION_BUCKET` | `copilot-sessions-<account>-ap-northeast-2` | 기억(M3) |
| `INJECTOR_FN` | `coffee-fault-injector` | SQL 실행 헬퍼 |
| `COFFEE_CUSTOMER_API` | `<CustomerApiUrl>` | 스모크 대상 |
| `COFFEE_EMPLOYEE_API` | `<EmployeeApiUrl>` | 스모크 대상 |
| `COFFEE_CUSTOMER_FN` | `coffee-customer` | 재배포 대상 |
| `COFFEE_EMPLOYEE_FN` | `coffee-employee` | 재배포 대상 |
| `CODE_BUCKET` | `coffee-lambda-code-<account>-apne2` | 정규 빌드 zip 위치 |
| `CUSTOMER_CLEAN_KEY` | `lambda/customer.zip` | 정규 빌드 키 |
| `EMPLOYEE_CLEAN_KEY` | `lambda/employee.zip` | 정규 빌드 키 |

---

## 7. 실행 역할(IAM) 권한 (Configuration → Permissions → 역할 클릭)

기본 실행 역할에 인라인 정책을 추가합니다 (요약):

- Bedrock: `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream` (Resource `*`)
- KB 검색: `bedrock:Retrieve` (해당 KB ARN)
- 로그 진단: `logs:FilterLogEvents`, `logs:GetLogEvents`, `logs:DescribeLogStreams`
  (`arn:aws:logs:ap-northeast-2:<account>:log-group:/aws/lambda/coffee-*`)
- 복구: `lambda:InvokeFunction` (injector), `lambda:UpdateFunctionCode`,
  `lambda:GetFunction`, `lambda:GetFunctionConfiguration` (coffee-customer/employee),
  `s3:GetObject` (CODE_BUCKET)
- 기억: `s3:GetObject/PutObject/DeleteObject/ListBucket` (SESSION_BUCKET)

> 정확한 JSON은 `infra/IncidentCopilot_CF.yaml` 의 `AgentRole` 를 그대로 복사해
> 쓰면 됩니다.

---

## 8. Function URL 만들기 (Configuration → Function URL → Create)

- **Auth type**: `NONE`
- **Invoke mode**: **RESPONSE_STREAM** (스트리밍에 필수)
- **CORS**: Allow origin `*`, methods `*`, headers `*`

생성 후, 이 계정은 퍼블릭 Function URL에 권한 2개가 더 필요합니다(콘솔에서 자동
추가 안 되면 CLI로):
```sh
FN=strands-incident-copilot
aws lambda add-permission --function-name $FN --statement-id PublicUrl \
  --action lambda:InvokeFunctionUrl --principal "*" --function-url-auth-type NONE
aws lambda add-permission --function-name $FN --statement-id PublicInvoke \
  --action lambda:InvokeFunction --principal "*"
```

---

## 9. 동작 확인

```sh
URL=<Function URL>
curl -s "$URL"                                  # {"ok":true}
curl -sN -X POST "$URL/chat" -H "Content-Type: application/json" \
  -d '{"message":"employee 이상해 조사해","session_id":"T1"}'
```

---

## 10. 콘솔에서 모듈 켜기 (학생 실습)

1. Lambda 콘솔 → 이 함수 → **Code** 탭 → 파일 트리에서 **`lambda_src/agent_app.py`** 열기
2. `build_agent` 안에서 원하는 모듈 줄의 맨 앞 `#` 을 지움
3. **Deploy** (Ctrl/Cmd + S 후 Deploy 버튼)
4. 채팅 웹에서 같은 질문으로 변화 확인

| 모듈 | 켜는 줄 |
|------|--------|
| 2 도구 | `tools=tools.ALL,` |
| 3 기억 | `session_manager=memory(session_id),` |
| 4 지식베이스 | `tools=tools.ALL + [knowledge_base.search],` |
| 5 AWS 문서 | `tools=tools.ALL + [knowledge_base.search] + aws_docs.load(),` |

> 코드가 작아(수십 KB) 콘솔 인라인 편집기가 열립니다. 서드파티 라이브러리는
> 레이어에 있어 보이지 않고, 프로젝트 코드(`lambda_src/`)만 보입니다.
