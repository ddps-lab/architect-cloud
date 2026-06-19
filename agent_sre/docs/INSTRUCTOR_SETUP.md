# 강사 사전 준비 (1회)

수강생 실습 전에 강사가 한 번 해두는 것들입니다.

## 0. 공유 산출물 발행 (전역 1회) — `publish_artifacts.sh`

CloudShell은 사양·용량이 빠듯해서 수강생이 직접 라이브러리 레이어(pip manylinux,
약 80MB)나 injector(npm)를 빌드하면 부담이 큽니다. 그래서 **강사가 한 번만 빌드**해
퍼블릭 읽기 공유 버킷에 올려두고, 수강생은 빌드 없이 `aws s3 cp` 로만 가져갑니다.

**CloudShell**(서울 리전)에서:

```sh
git clone https://github.com/ddps-lab/architect-cloud.git
cd architect-cloud/agent_sre
./infra/publish_artifacts.sh         # injector.zip + layer.zip 빌드 → 공유 버킷 업로드
# 출력된 SHARED_BUCKET 이름을 수강생에게 공유
```

> 기본 공유 버킷명은 `copilot-artifacts-<강사계정>-apne2` 입니다. 수강생용
> `deploy_labbase.sh` 의 기본값(`copilot-artifacts-786382940258-apne2`)과 다르면,
> 수강생에게 `SHARED_BUCKET=<버킷명>` 을 앞에 붙여 실행하도록 안내하세요.
> 산출물(Strands/awslabs 등)을 갱신했을 때만 다시 실행하면 됩니다.

## 1. 공유 채팅 웹 배포 (전역 1회)

정적 채팅 SPA를 한 벌만 배포하고, 그 URL을 모든 수강생에게 공유합니다. 수강생은
각자 자신의 에이전트 Function URL을 화면 ⚙︎설정에 입력해서 씁니다.

**CloudShell**(서울 리전)에서:

```sh
git clone https://github.com/ddps-lab/architect-cloud.git
cd architect-cloud/agent_sre
./web-chat/deploy_chat.sh            # copilot-chat-web 스택 생성 + SPA 업로드
# 출력된 "채팅 사이트" URL 을 수강생에게 공유
```

> 수강생 개별 배포 대상이 아닙니다. 한 번만 만들면 됩니다.

## 2. 수강생에게 안내할 것

- 이 저장소(`agent_sre/`)
- 공유 채팅 사이트 URL (위 1번 출력)
- **공유 산출물 버킷명** `SHARED_BUCKET` (위 0번 출력) — 기본값과 다를 때만
- 각자 **자기 AWS 환경에 `coffee-serverless` 스택이 배포돼 있어야 함**
  (대상 마이크로서비스 + RDS). → `../cloudformation/ServerlessApp_CF.yaml`
- Bedrock 모델 액세스 활성화(ap-northeast-2): 사용할 모델 + Titan Text Embeddings v2
- 실습 절차: `docs/STUDENT_GUIDE.md`

## 책임 분담 요약

| 구분 | 누가 | 무엇 |
|------|------|------|
| **공유 산출물(injector.zip·layer.zip) 빌드·발행** | 강사(1회) | `infra/publish_artifacts.sh` → 퍼블릭 버킷 |
| 공유 채팅 웹 | 강사(1회) | S3+CloudFront SPA (`web-chat/`) |
| coffee-serverless | 수강생(각자) | 대상 서비스 + RDS |
| LabBase (injector·IAM 역할·세션버킷·레이어) | 수강생(각자, CF) | `infra/deploy_labbase.sh` (빌드 없이 cp) |
| **S3 Vectors / Knowledge Base / 적재** | **수강생(직접)** | 핵심 실습 |
| **에이전트 Lambda 생성·편집** | **수강생(직접, 콘솔)** | 핵심 실습 |
| 장애 주입 | 수강생(각자) | `faults/inject.sh` (자기 RDS 대상) |
