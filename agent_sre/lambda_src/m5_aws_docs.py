"""AWS 공식문서 MCP 도구 로더 (완성품).

학생은 agent_app.py 에서 `m5_aws_docs.load()` 를 도구 목록에 더하면 됩니다.
MCP 서버(awslabs.aws-documentation-mcp-server)는 Lambda 패키지에 번들되어 있어
`python -m ...` 서브프로세스로 한 번 띄워 재사용합니다.
"""
import os

from mcp import StdioServerParameters, stdio_client
from strands.tools.mcp import MCPClient

_client = None
_tools = None


def load():
    """AWS 문서 MCP 도구 목록을 반환합니다(컨테이너당 한 번만 서버 기동)."""
    global _client, _tools
    if _tools is None:
        env = dict(os.environ)
        env["AWS_DOCUMENTATION_PARTITION"] = os.environ.get("AWS_DOCUMENTATION_PARTITION", "aws")
        _client = MCPClient(
            lambda: stdio_client(
                StdioServerParameters(
                    command=os.environ.get("MCP_PYTHON", "python3.12"),
                    args=["-m", "awslabs.aws_documentation_mcp_server.server"],
                    env=env,
                )
            )
        )
        _client.start()
        _tools = _client.list_tools_sync()
    return list(_tools)
