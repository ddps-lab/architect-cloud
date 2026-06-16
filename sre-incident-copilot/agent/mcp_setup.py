"""M5 — MCP: AWS official documentation server (knowledge-cutoff buster).

Connects to awslabs.aws-documentation-mcp-server (run locally via uvx) and exposes
its tools to the agent. This lets the agent answer questions about AWS features
released after the model's training cutoff by reading current AWS docs and citing
source URLs.

Local registration (one line, via uvx):
  {
    "mcpServers": {
      "awslabs.aws-documentation-mcp-server": {
        "command": "uvx",
        "args": ["awslabs.aws-documentation-mcp-server@latest"],
        "env": { "AWS_DOCUMENTATION_PARTITION": "aws" }
      }
    }
  }

Usage:
  from agent.mcp_setup import aws_docs_client
  with aws_docs_client() as client:
      tools = client.list_tools_sync()
      agent = Agent(model=..., system_prompt=..., tools=[*tools, *other_tools])

Note: MCP-over-stdio (uvx) is intended for LOCAL development of the agent. The
deployed Lambda (M6) runs without the MCP server; agent.py includes MCP tools only
when ENABLE_MCP is set, so the same code works locally and in Lambda.
"""
import os
import shutil

from mcp import StdioServerParameters, stdio_client
from strands.tools.mcp import MCPClient


def aws_docs_client() -> MCPClient:
    """Return a Strands MCPClient bound to the AWS documentation MCP server.

    Raises a clear error if `uvx` is not installed locally.
    """
    if shutil.which("uvx") is None:
        raise RuntimeError(
            "uvx not found. Install uv (https://docs.astral.sh/uv/) to run the "
            "AWS documentation MCP server locally."
        )
    return MCPClient(
        lambda: stdio_client(
            StdioServerParameters(
                command="uvx",
                args=["awslabs.aws-documentation-mcp-server@latest"],
                env={"AWS_DOCUMENTATION_PARTITION": os.environ.get("AWS_DOCUMENTATION_PARTITION", "aws")},
            )
        )
    )
