"""coffee_sre — SRE Incident Copilot 프레임워크(숨김).

학생은 이 패키지를 수정하지 않습니다. solution.py 에서 아래만 가져다 씁니다:

    from coffee_sre import tools, knowledge_base, aws_docs, memory, model, SYSTEM_PROMPT
"""
from .prompt import SYSTEM_PROMPT
from .model import model
from .memory import memory
from . import tools, knowledge_base, aws_docs

__all__ = ["SYSTEM_PROMPT", "model", "memory", "tools", "knowledge_base", "aws_docs"]
