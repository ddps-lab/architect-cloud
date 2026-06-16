#!/bin/bash
# Lambda Web Adapter startup command (Handler = run.sh). Boots the FastAPI app
# with uvicorn; LWA proxies the Function URL request to it and streams the SSE
# response back (AWS_LWA_INVOKE_MODE=response_stream).
PATH=$PATH:$LAMBDA_TASK_ROOT/bin \
PYTHONPATH=$PYTHONPATH:$LAMBDA_TASK_ROOT:/opt/python:$LAMBDA_RUNTIME_DIR \
    exec python3.12 -m uvicorn agent.server:app --host 0.0.0.0 --port "${PORT:-8000}"
