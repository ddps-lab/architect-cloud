"""LLM 모델 헬퍼. 학생이 건드릴 필요 없음.

model() 은 Bedrock 모델 객체를 만들어 줍니다. 어떤 모델/리전을 쓸지는 환경변수
(MODEL_ID, BEDROCK_REGION)로 정해집니다.
"""
import os

from strands.models import BedrockModel

MODEL_ID = os.environ.get("MODEL_ID", "global.anthropic.claude-sonnet-4-6")
REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
# 모델 호출만 다른 리전으로 보낼 수 있음(로그/람다/KB는 스택 리전 유지).
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", REGION)


def model() -> BedrockModel:
    """에이전트가 사용할 LLM을 만들어 반환합니다."""
    return BedrockModel(model_id=MODEL_ID, region_name=BEDROCK_REGION, temperature=0.2)
