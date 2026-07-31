#!/bin/sh
# Lambda Web Adapter startup script (function Handler). The adapter
# layer's own /opt/bootstrap invokes this via AWS_LAMBDA_EXEC_WRAPPER.
#
# Starts mcp-proxy, a generic stdio<->streamable-HTTP bridge, which spawns
# the standard, unmodified `uvx awslabs.redshift-mcp-server@latest` as its
# stdio backend -- the exact same command as the standard stdio MCP config:
#
#   { "mcpServers": { "awslabs.redshift-mcp-server":
#       { "command": "uvx", "args": ["awslabs.redshift-mcp-server@latest"] } } }
#
# No forked/custom MCP server code ships in this deployment -- the server
# itself is always pulled fresh from PyPI on cold start.
set -e

export PYTHONPATH="/var/task"

# pip installs console-script binaries (uv, uvx, mcp-proxy) under a
# "<package>-<version>.data/scripts" directory when using `pip install
# --target`, not a top-level bin/ -- the exact folder name varies by pip
# version and build environment, so locate it dynamically instead of
# hardcoding a path.
for d in /var/task/*.data/scripts; do
  [ -d "$d" ] && export PATH="${d}:${PATH}"
done
export PATH="/var/task/bin:${PATH}"

# uv/uvx cache and home dirs must be writable; /tmp is the only writable
# path in the Lambda execution environment.
export HOME=/tmp
export UV_CACHE_DIR=/tmp/uv-cache
export UV_TOOL_DIR=/tmp/uv-tools
export UV_PYTHON_INSTALL_DIR=/tmp/uv-python

exec python3 -m mcp_proxy --port=8000 --host=0.0.0.0 --stateless --pass-environment -- \
  uvx awslabs.redshift-mcp-server@latest
