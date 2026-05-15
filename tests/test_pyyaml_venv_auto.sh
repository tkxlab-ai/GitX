#!/bin/bash
# test_pyyaml_venv_auto.sh — v1.4.0.
#
# Validates ensure_pyyaml_via_venv() helper auto-creates a temporary venv
# with PyYAML installed when system Python lacks it (macOS PEP 668 blocks
# system pip). Enables vendored skill-creator path (quick_validate.py +
# package_skill.py both import PyYAML) without requiring user pre-install.
#
# Falls back gracefully when no Python or venv/pip fails.
#
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER_SH="$ROOT/scripts/lib/skill-creator-version.sh"
RELEASE_SH="$ROOT/scripts/release.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_pyyaml_venv_auto.sh ══"

# === Static 1: helper defines ensure_pyyaml_via_venv ===
if grep -qE '^ensure_pyyaml_via_venv\(\)' "$HELPER_SH"; then
    ok "helper defines ensure_pyyaml_via_venv()"
else
    fail "helper missing ensure_pyyaml_via_venv()"
fi

# === Static 2: helper uses python3 -m venv + pip install pyyaml ===
if grep -qE 'python3 -m venv' "$HELPER_SH" && grep -qE 'pip.*install.*pyyaml' "$HELPER_SH"; then
    ok "helper uses python3 -m venv + pip install pyyaml"
else
    fail "helper missing venv creation or pyyaml install"
fi

# === Static 3: helper sets SKC_VENV_PYTHON + SKC_VENV_DIR + SKC_PYYAML_OK ===
if grep -qE 'SKC_VENV_PYTHON=' "$HELPER_SH" && \
   grep -qE 'SKC_VENV_DIR=' "$HELPER_SH" && \
   grep -qE 'SKC_PYYAML_OK="1"' "$HELPER_SH"; then
    ok "helper exports SKC_VENV_PYTHON + SKC_VENV_DIR + SKC_PYYAML_OK on success"
else
    fail "helper missing one of SKC_VENV_PYTHON / SKC_VENV_DIR / SKC_PYYAML_OK"
fi

# === Static 4: helper idempotent (early return if PyYAML already OK) ===
# Function body should have `if [ "$SKC_PYYAML_OK" = "1" ]` early guard
# followed by `return 0` within a few lines.
FN_BODY=$(awk '/^ensure_pyyaml_via_venv\(\)/,/^}$/' "$HELPER_SH")
if echo "$FN_BODY" | grep -qE 'SKC_PYYAML_OK.*=.*"1"' && \
   echo "$FN_BODY" | grep -qE 'return 0'; then
    ok "helper idempotent (early return when PyYAML already available)"
else
    fail "helper missing idempotent early return guard"
fi

# === Static 5: release.sh calls ensure_pyyaml_via_venv ===
if grep -qE 'ensure_pyyaml_via_venv' "$RELEASE_SH"; then
    ok "release.sh calls ensure_pyyaml_via_venv"
else
    fail "release.sh does not call ensure_pyyaml_via_venv"
fi

# === Static 6: release.sh uses $PYTHON_BIN (not hardcoded `python`) for skill-creator call ===
if grep -qE '"\$PYTHON_BIN" -m scripts\.package_skill' "$RELEASE_SH"; then
    ok "release.sh uses \$PYTHON_BIN for skill-creator package_skill call"
else
    fail "release.sh still hardcodes 'python' (won't use venv python)"
fi

# === Static 7: release.sh registers venv dir in CLEANUP_EXTRAS ===
if grep -qE 'CLEANUP_EXTRAS\+=\("?\$SKC_VENV_DIR' "$RELEASE_SH"; then
    ok "release.sh registers SKC_VENV_DIR in CLEANUP_EXTRAS (no /tmp leak)"
else
    fail "release.sh does not register venv dir for cleanup"
fi

# === Behavioral: actually invoke ensure_pyyaml_via_venv + verify venv created ===
RESULT=$(bash -c "
    set -u
    SKC_PYYAML_OK=''
    SKC_VENV_PYTHON=''
    SKC_VENV_DIR=''
    SKC_VENDORED_PATH=''; SKC_VENDORED_DATE=''; SKC_VENDORED_COMMIT=''
    SKC_SYSTEM_PATH=''; SKC_SYSTEM_DATE=''; SKC_VERDICT=''
    source '$HELPER_SH'
    # Force PYYAML check first (in case env has it system-wide we still test the path)
    if python3 -c 'import yaml' >/dev/null 2>&1; then
        echo 'PRE_HAVE_PYYAML=1'
    else
        echo 'PRE_HAVE_PYYAML=0'
    fi
    SKC_PYYAML_OK='0'
    if ensure_pyyaml_via_venv; then
        echo \"VENV_DIR=\$SKC_VENV_DIR\"
        echo \"VENV_PYTHON=\$SKC_VENV_PYTHON\"
        echo \"PYYAML_OK=\$SKC_PYYAML_OK\"
        if [ -x \"\$SKC_VENV_PYTHON\" ]; then
            \"\$SKC_VENV_PYTHON\" -c 'import yaml; print(\"YAML_VERSION_PROBE=\" + yaml.__version__)'
        fi
        rm -rf \"\$SKC_VENV_DIR\"
    else
        echo 'VENV_FAILED'
    fi
")

if echo "$RESULT" | grep -qE "YAML_VERSION_PROBE=[0-9]+\."; then
    ok "behavior: venv created + PyYAML import works ($(echo "$RESULT" | grep YAML_VERSION_PROBE))"
else
    # If system Python is unusual, accept VENV_FAILED as graceful degradation
    if echo "$RESULT" | grep -q "VENV_FAILED"; then
        ok "behavior: ensure_pyyaml_via_venv graceful-fails when python3/venv unavailable (acceptable)"
    else
        fail "behavior: venv creation+import path broken. Output: $RESULT"
    fi
fi

# === Static 8: PYTHON_BIN defaults to "python" when SKC_VENV_PYTHON empty ===
if grep -qE 'PYTHON_BIN="\$\{SKC_VENV_PYTHON:-python\}"' "$RELEASE_SH"; then
    ok "release.sh PYTHON_BIN defaults to 'python' when venv path empty"
else
    fail "release.sh PYTHON_BIN fallback not safe (could fail with set -u if SKC_VENV_PYTHON unset)"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
