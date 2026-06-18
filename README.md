# Cloud Architect 양성과정

**한양대학교 분산데이터처리시스템연구실(DDPS Lab, [ddps.cloud](https://ddps.cloud/))** 과
함께하는 클라우드 아키텍트 양성과정 실습 저장소입니다.

하나의 예제 서비스(**coffee** 공급사 관리 앱)를 모놀리식에서 시작해 마이크로서비스,
컨테이너·쿠버네티스, 서버리스, 그리고 AI 에이전트 기반 운영(SRE)까지 단계적으로
발전시키며 클라우드 아키텍처의 핵심 개념을 직접 손으로 익힙니다.

## 실습 여정

| 단계 | 주제 | 디렉터리 |
|------|------|----------|
| 1 | 모놀리식 애플리케이션 | [`monolithic_code/`](monolithic_code/) |
| 2 | 마이크로서비스 분리 (customer / employee) | [`microservice/`](microservice/) |
| 3 | 컨테이너 & 쿠버네티스 / EKS (HPA·Karpenter·ALB) | [`kubernetes/`](kubernetes/) |
| 4 | 서버리스 (Lambda + API Gateway + S3 + CloudFront) | [`cloudformation/`](cloudformation/), [`lambda_code/`](lambda_code/) |
| 5 | 정적 프론트엔드 (S3 호스팅) | [`s3_customer/`](s3_customer/), [`s3_employee/`](s3_employee/) |
| 6 | AI 에이전트 SRE 인시던트 코파일럿 | [`agent_sre/`](agent_sre/) |

## 디렉터리 안내

- **`monolithic_code/`** — Node.js 기반 단일 서버 앱. 출발점.
- **`microservice/`** — customer / employee 서비스로 분리한 마이크로서비스 코드.
- **`kubernetes/`** — Deployment·Service·Ingress·HPA·Karpenter 등 EKS 실습 매니페스트.
- **`lambda_code/`** — 모놀리식 / 마이크로서비스 버전의 Lambda 핸들러 코드.
- **`cloudformation/`** — 인프라 IaC 템플릿
  (`MSA_CF.yaml`: 컨테이너/MSA, `ServerlessApp_CF.yaml`: VPC+RDS+Lambda+API GW+S3+CloudFront).
- **`s3_customer/` · `s3_employee/`** — S3 정적 호스팅용 프론트엔드.
- **`utils/`** — 실습 보조 스크립트 (EKS·Docker·ALB·Locust 설치, Lambda 패키징,
  프론트엔드 배포 등).
- **`agent_sre/`** — AWS Strands 에이전트로 coffee 서비스 장애를
  탐지→진단→복구→검증하는 SRE 실습. 자세한 내용은

## 사전 준비
- 실습은 대부분 **서울 리전(ap-northeast-2)** 기준
- 단계별 상세 절차는 각 디렉터리의 문서 및 강의 자료를 참고하세요.


© 한양대학교 분산데이터처리시스템연구실 (DDPS Lab) — Cloud Architect 양성과정
· [ddps.cloud](https://ddps.cloud/)
