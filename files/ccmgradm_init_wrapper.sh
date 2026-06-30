#!/bin/bash
# ccmgradm_init_wrapper.sh
# Wraps `ccmgradm init` and treats "Controller already exists" as success.
#
# This is needed because ccmgradm returns exit code 1 when the controller
# is already registered, which is actually an idempotent success - the
# desired state (controller registered with correct frontend path) is met.
#
# Usage: ccmgradm_init_wrapper.sh <port> <web_root>

set -e

PORT="${1:?Usage: $0 <port> <web_root>}"
WEB_ROOT="${2:?Usage: $0 <port> <web_root>}"

# Run ccmgradm init and capture output + real exit code (don't lose RC in || true)
set +e
OUTPUT="$(ccmgradm init --local-cmon -p "$PORT" -f "$WEB_ROOT" 2>&1)"
RC=$?
set -e

# Always show the output for transparency
echo "$OUTPUT"

# Exit 0 if either:
#   - ccmgradm reported success (exit 0)
#   - Controller already exists (already in desired state)
#   - Controller registered successfully
if [ "$RC" -eq 0 ]; then
    exit 0
fi

if echo "$OUTPUT" | grep -qi "controller already exists"; then
    echo "INFO: Controller already registered - treating as success (idempotent)"
    exit 0
fi

if echo "$OUTPUT" | grep -qi "registered successfully"; then
    echo "INFO: Controller registered successfully"
    exit 0
fi

# Genuine failure
echo "ERROR: ccmgradm init failed with exit code $RC"
exit "$RC"
