"""lambda_src — SRE Incident Copilot 프레임워크.

이 패키지는 Lambda 함수 코드에 포함됩니다(콘솔에서 보입니다). 학생이 주로
편집하는 파일은 lambda_src/agent_app.py 입니다. 거기서 아래를 가져다 씁니다:

    from lambda_src import tools, knowledge_base, aws_docs, memory, model, SYSTEM_PROMPT
"""
from .prompt import SYSTEM_PROMPT
from .model import model
from .memory import memory
from . import tools, knowledge_base, aws_docs

__all__ = ["SYSTEM_PROMPT", "model", "memory", "tools", "knowledge_base", "aws_docs"]
