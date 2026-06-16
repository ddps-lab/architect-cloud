"""Assemble the SRE Incident Copilot agent from the module pieces.

Each capability can be toggled so the lab can demonstrate the before/after for
every module (M1 skeleton only -> add tools -> memory -> KB -> MCP).
"""
import os

from strands import Agent
from strands.models import BedrockModel

from .system_prompt import SYSTEM_PROMPT
from .tools_operational import OPERATIONAL_TOOLS
from .memory import MEMORY_TOOLS

# claude-sonnet-4-6 in ap-northeast-2 (override via env; an inference-profile id
# such as "apac.anthropic.claude-sonnet-4-6" may be required depending on account).
DEFAULT_MODEL_ID = os.environ.get("MODEL_ID", "anthropic.claude-sonnet-4-6")
REGION = os.environ.get("AWS_REGION", "ap-northeast-2")


def build_model(model_id: str = DEFAULT_MODEL_ID) -> BedrockModel:
    return BedrockModel(model_id=model_id, region_name=REGION, temperature=0.2)


def build_agent(
    enable_tools: bool = True,
    enable_memory: bool = True,
    mcp_tools=None,
    model_id: str = DEFAULT_MODEL_ID,
) -> Agent:
    """Build an agent with a selectable set of capabilities.

    Args:
        enable_tools: include operational tools (smoke/logs/kb_search/apply_recovery).
        enable_memory: include the DynamoDB incident-timeline tools.
        mcp_tools: optional list of MCP tools (e.g. AWS docs) to add (M5).
        model_id: Bedrock model id / inference profile.
    """
    tools = []
    if enable_tools:
        tools += OPERATIONAL_TOOLS
    if enable_memory:
        tools += MEMORY_TOOLS
    if mcp_tools:
        tools += list(mcp_tools)

    return Agent(model=build_model(model_id), system_prompt=SYSTEM_PROMPT, tools=tools)
