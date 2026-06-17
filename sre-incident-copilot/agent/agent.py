"""Assemble the SRE Incident Copilot agent from the module pieces.

Each capability can be toggled so the lab can demonstrate the before/after for
every module (M1 skeleton only -> add tools -> memory -> KB -> MCP).

Memory (M3+) uses Strands' built-in S3SessionManager: the agent's conversation
state is persisted to S3 per session_id and restored on the next request, so
multi-turn incidents survive Lambda's stateless invocations — no custom store.
"""
import os

from strands import Agent
from strands.models import BedrockModel
from strands.session.s3_session_manager import S3SessionManager

from .system_prompt import SYSTEM_PROMPT
from .tools_operational import OPERATIONAL_TOOLS, KB_TOOLS

# Default model = Amazon Nova Micro (on-demand requires an inference profile; this
# one uses the APAC regional profile). Override via the MODEL_ID env var.
DEFAULT_MODEL_ID = os.environ.get("MODEL_ID", "apac.amazon.nova-micro-v1:0")
REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
# Bedrock model invocation can target a different region than the rest of the
# stack (logs/lambda/KB stay in AWS_REGION). Set BEDROCK_REGION to e.g. us-east-1
# to use models only offered there.
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", REGION)
# S3 bucket for Strands session persistence (memory).
SESSION_BUCKET = os.environ.get("SESSION_BUCKET")


def build_model(model_id: str = DEFAULT_MODEL_ID) -> BedrockModel:
    return BedrockModel(model_id=model_id, region_name=BEDROCK_REGION, temperature=0.2)


def build_agent(
    enable_tools: bool = True,
    enable_memory: bool = True,
    enable_kb: bool = True,
    mcp_tools=None,
    model_id: str = DEFAULT_MODEL_ID,
    callback_handler=None,
    session_id: str | None = None,
) -> Agent:
    """Build an agent with a selectable set of capabilities.

    Args:
        enable_tools: include operational tools (smoke/logs/run_sql/redeploy).
        enable_memory: persist/restore conversation state via S3SessionManager.
        enable_kb: include kb_search (post-mortem KB retrieval, M4+).
        mcp_tools: optional list of MCP tools (e.g. AWS docs) to add (M5).
        model_id: Bedrock model id / inference profile.
        callback_handler: Strands callback handler; default None (no stream print).
        session_id: incident/chat session id (required for memory).
    """
    tools = []
    if enable_tools:
        tools += OPERATIONAL_TOOLS
    if enable_kb:
        tools += KB_TOOLS
    if mcp_tools:
        tools += list(mcp_tools)

    session_manager = None
    if enable_memory and session_id and SESSION_BUCKET:
        session_manager = S3SessionManager(
            session_id=session_id,
            bucket=SESSION_BUCKET,
            prefix="copilot-sessions/",
            region_name=REGION,
        )

    return Agent(
        model=build_model(model_id),
        system_prompt=SYSTEM_PROMPT,
        tools=tools,
        callback_handler=callback_handler,
        session_manager=session_manager,
    )


# Capability matrix per lab module — the Lambda flips MODULE to progress.
MODULE_SPECS = {
    "m1": dict(enable_tools=False, enable_memory=False, enable_kb=False),  # skeleton only
    "m2": dict(enable_tools=True, enable_memory=False, enable_kb=False),   # + operational tools
    "m3": dict(enable_tools=True, enable_memory=True, enable_kb=False),    # + memory (S3 session)
    "m4": dict(enable_tools=True, enable_memory=True, enable_kb=True),     # + KB retrieval (kb_search)
    "m5": dict(enable_tools=True, enable_memory=True, enable_kb=True),     # + MCP (added by caller)
}


def build_agent_for_module(module: str, mcp_tools=None, callback_handler=None, session_id: str | None = None) -> Agent:
    """Build the agent at a given lab module level (m1..m5)."""
    spec = MODULE_SPECS.get(module, MODULE_SPECS["m4"])
    return build_agent(
        enable_tools=spec["enable_tools"],
        enable_memory=spec["enable_memory"],
        enable_kb=spec["enable_kb"],
        mcp_tools=mcp_tools,
        callback_handler=callback_handler,
        session_id=session_id,
    )
