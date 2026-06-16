#!/usr/bin/env python3
"""Local runner for the SRE Incident Copilot — drives the module before/after demos.

Examples:
  # M1 (skeleton only, no tools): it should refuse to guess and ask for evidence
  python steps/run_local.py --module m1 --once "customer 서비스가 죽었어. 원인이 뭐야?"

  # M2 (tools): it pulls real logs + runs a smoke test
  python steps/run_local.py --module m2 --once "customer가 이상해. 조사해줘."

  # M3 (memory) / M4 (KB is on whenever tools are on) — interactive
  python steps/run_local.py --module m3

  # M5 (AWS docs MCP): answer a post-cutoff AWS question with citations
  python steps/run_local.py --module m5 --once "최근 출시된 Amazon S3 Vectors의 Bedrock KB 사용법 알려줘"

Requires AWS creds + the IncidentCopilot stack env (KB_ID, INCIDENT_TABLE, ...).
Export them or run after deploy. See README.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from agent.agent import build_agent  # noqa: E402

MODULES = {
    "m1": dict(enable_tools=False, enable_memory=False, mcp=False),  # skeleton only
    "m2": dict(enable_tools=True, enable_memory=False, mcp=False),   # + operational tools
    "m3": dict(enable_tools=True, enable_memory=True, mcp=False),    # + memory
    "m4": dict(enable_tools=True, enable_memory=True, mcp=False),    # KB on (via kb_search)
    "m5": dict(enable_tools=True, enable_memory=True, mcp=True),     # + AWS docs MCP
}


def make_agent(spec):
    if spec["mcp"]:
        from agent.mcp_setup import aws_docs_client

        client = aws_docs_client()
        client.start()
        tools = client.list_tools_sync()
        return build_agent(enable_tools=spec["enable_tools"], enable_memory=spec["enable_memory"], mcp_tools=tools), client
    return build_agent(enable_tools=spec["enable_tools"], enable_memory=spec["enable_memory"]), None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--module", choices=MODULES.keys(), default="m4")
    ap.add_argument("--once", help="single prompt, then exit")
    args = ap.parse_args()

    spec = MODULES[args.module]
    print(f"== SRE Incident Copilot [{args.module}] "
          f"(tools={spec['enable_tools']} memory={spec['enable_memory']} mcp={spec['mcp']}) ==")
    agent, client = make_agent(spec)
    try:
        if args.once:
            print(agent(args.once))
            return
        print("type your message (Ctrl-C to exit)")
        while True:
            msg = input("\nyou> ").strip()
            if not msg:
                continue
            print("\ncopilot>", agent(msg))
    except (KeyboardInterrupt, EOFError):
        print("\nbye")
    finally:
        if client:
            client.stop(None, None, None)


if __name__ == "__main__":
    main()
