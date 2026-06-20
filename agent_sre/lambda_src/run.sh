#!/bin/bash
# Lambda Web Adapter startup command (Handler = run.sh). Boots the chat runtime
# with uvicorn; LWA proxies the Function URL request and streams the SSE response
# back (AWS_LWA_INVOKE_MODE=response_stream). The runtime imports the student's
# agent_app.build_agent.
PATH=$PATH:$LAMBDA_TASK_ROOT/bin \
PYTHONPATH=$PYTHONPATH:$LAMBDA_TASK_ROOT:/opt/python:$LAMBDA_RUNTIME_DIR \
    exec python3.14 -m uvicorn lambda_src.runtime:app --host 0.0.0.0 --port "${PORT:-8000}"
