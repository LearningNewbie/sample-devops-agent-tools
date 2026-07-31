#!/bin/bash
# Builds the .zip deployment package for the Lambda "proxy" variant.
#
# Installs uv and mcp-proxy targeting manylinux2014_aarch64 / Python 3.13
# wheels directly via `pip install --platform`, with no container runtime
# required. Every dependency in this tree (uv, mcp-proxy, and transitive
# deps like cryptography and pydantic-core) publishes prebuilt manylinux
# wheels for arm64, so this produces the exact same result as building
# inside a Lambda-compatible container -- just without needing Docker or
# Finch installed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
ZIP_PATH="${SCRIPT_DIR}/redshift-mcp-proxy-lambda.zip"

PYTHON_BIN="$(command -v python3.13 || command -v python3 || command -v python)"
if [[ -z "${PYTHON_BIN}" ]]; then
  echo "ERROR: no python3 interpreter found on PATH." >&2
  exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

"${PYTHON_BIN}" -m pip install --no-cache-dir \
  --platform manylinux2014_aarch64 \
  --python-version 3.13 \
  --implementation cp \
  --abi cp313 \
  --only-binary=:all: \
  --target "${BUILD_DIR}" \
  uv mcp-proxy

cat > "${BUILD_DIR}/run.sh" <<'EOF'
#!/bin/sh
# Lambda Web Adapter startup script (set as the function Handler). The
# adapter layer's own /opt/bootstrap invokes this via AWS_LAMBDA_EXEC_WRAPPER.
# Starts mcp-proxy, which spawns the standard, unmodified
# `uvx awslabs.redshift-mcp-server@latest` as its stdio backend -- the same
# command as the standard stdio MCP config.
export PYTHONPATH="/var/task"
# pip installs console-script binaries (uv, uvx, mcp-proxy) under a
# "<package>-<version>.data/scripts" directory when using `pip install
# --target`, not always a top-level bin/ -- the exact folder name varies by
# pip version and build environment, so locate it dynamically instead of
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
EOF
chmod 755 "${BUILD_DIR}/run.sh"

rm -f "${ZIP_PATH}"
(cd "${BUILD_DIR}" && zip -q -r "${ZIP_PATH}" . -x '__pycache__/*' -x '*/__pycache__/*')
echo "Package built:"
ls -la "${ZIP_PATH}"
unzip -l "${ZIP_PATH}" | tail -5
