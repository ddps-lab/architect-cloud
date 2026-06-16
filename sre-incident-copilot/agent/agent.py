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

# Default model = Amazon Nova 2 Lite (on-demand requires an inference profile, so
# the global cross-region profile id). Override via the MODEL_ID env var.
DEFAULT_MODEL_ID = os.environ.get("MODEL_ID", "global.amazon.nova-2-lite-v1:0")
REGION = os.environ.get("AWS_REGION", "ap-northeast-2")


def build_model(model_id: str = DEFAULT_MODEL_ID) -> BedrockModel:
    return BedrockModel(model_id=model_id, region_name=REGION, temperature=0.2)


def build_agent(
    enable_tools: bool = True,
    enable_memory: bool = True,
    mcp_tools=None,
    model_id: str = DEFAULT_MODEL_ID,
    callback_handler=None,
) -> Agent:
    """Build an agent with a selectable set of capabilities.

    Args:
        enable_tools: include operational tools (smoke/logs/kb_search/apply_recovery).
        enable_memory: include the DynamoDB incident-timeline tools.
        mcp_tools: optional list of MCP tools (e.g. AWS docs) to add (M5).
        model_id: Bedrock model id / inference profile.
        callback_handler: Strands callback handler; default None (no stream print).
    """
    tools = []
    if enable_tools:
        tools += OPERATIONAL_TOOLS
    if enable_memory:
        tools += MEMORY_TOOLS
    if mcp_tools:
        tools += list(mcp_tools)

    return Agent(
        model=build_model(model_id),
        system_prompt=SYSTEM_PROMPT,
        tools=tools,
        callback_handler=callback_handler,
    )


# Capability matrix per lab module — the Lambda flips MODULE to progress.
MODULE_SPECS = {
    "m1": dict(enable_tools=False, enable_memory=False),  # skeleton only
    "m2": dict(enable_tools=True, enable_memory=False),   # + operational tools
    "m3": dict(enable_tools=True, enable_memory=True),    # + memory
    "m4": dict(enable_tools=True, enable_memory=True),    # KB on (via kb_search)
    "m5": dict(enable_tools=True, enable_memory=True),    # + MCP (added by caller)
}


def build_agent_for_module(module: str, mcp_tools=None, callback_handler=None) -> Agent:
    """Build the agent at a given lab module level (m1..m5)."""
    spec = MODULE_SPECS.get(module, MODULE_SPECS["m4"])
    return build_agent(
        enable_tools=spec["enable_tools"],
        enable_memory=spec["enable_memory"],
        mcp_tools=mcp_tools,
        callback_handler=callback_handler,
    )
