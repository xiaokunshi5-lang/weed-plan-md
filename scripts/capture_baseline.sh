#!/usr/bin/env bash
# 在可信稳定版本上捕获测试、核心回归、冒烟、静态检查与性能数值基线。
# 用法: ./scripts/capture_baseline.sh <stable-git-ref> [--allow-known-test-failures]
set -uo pipefail

STABLE_REF="${1:-}"
ALLOW_KNOWN_FAILURES="${2:-}"
CONTRACT_PATH=".agents/PROJECT_CONTRACT.md"
BASELINE_DIR=".agents/baseline"

TEST_CMD=""
LINT_CMD=""
BENCH_CMD=""
CORE_REGRESSION_CMD=""
SMOKE_CMD=""
FAILURE_SIGNATURE_CMD=""
BENCH_THRESHOLD="${BENCH_THRESHOLD:-3}"
BENCH_HIGHER_IS_BETTER="0"
PERF_CRITICAL="${PERF_CRITICAL:-0}"
STAGING_DIR=""
PREVIOUS_DIR=""
if [ -f ".agents/workflow.config" ]; then
    # shellcheck disable=SC1091
    if ! source ".agents/workflow.config"; then
        echo "❌ 本地证据配置无法加载: .agents/workflow.config" >&2
        exit 1
    fi
fi
CONTRACT_PATH="${CONTRACT_PATH:-.agents/PROJECT_CONTRACT.md}"

cleanup_staging() {
    if [ -n "$PREVIOUS_DIR" ] && [ -d "$PREVIOUS_DIR" ]; then
        if [ ! -e "$BASELINE_DIR" ]; then
            mv "$PREVIOUS_DIR" "$BASELINE_DIR"
        else
            rm -rf "$PREVIOUS_DIR"
        fi
    fi
    if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
        rm -rf "$STAGING_DIR"
    fi
}
trap cleanup_staging EXIT

sha256_text() {
    printf '%s' "$1" | shasum -a 256 2>/dev/null | awk '{print $1}' \
        || printf '%s' "$1" | sha256sum 2>/dev/null | awk '{print $1}'
}

sha256_file() {
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' \
        || sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

evidence_digest() {
    local dir="$1" f payload
    payload=$(
        for f in manifest.env test.cmd core.cmd smoke.cmd lint.cmd bench.cmd signature.cmd test.signatures bench.value; do
            printf 'FILE:%s\n' "$f"
            if [ -f "${dir}/${f}" ]; then
                cat "${dir}/${f}"
            else
                printf '__MISSING__\n'
            fi
        done
    )
    sha256_text "$payload"
}

detect_test_cmd() {
    if [ -n "$TEST_CMD" ]; then echo "$TEST_CMD"; return; fi
    if [ -f package.json ]; then
        echo "npm test --silent"
    elif [ -f Cargo.toml ]; then
        echo "cargo test --quiet"
    elif [ -f go.mod ]; then
        echo "go test ./..."
    elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f requirements.txt ] || [ -f setup.py ] \
        || { [ -d tests ] && find tests -maxdepth 2 -name '*.py' -print -quit | grep -q .; }; then
        if command -v pytest >/dev/null 2>&1; then echo "pytest -q"; else echo "python3 -m unittest discover -s tests"; fi
    fi
}

detect_lint_cmd() {
    if [ -n "$LINT_CMD" ]; then echo "$LINT_CMD"; return; fi
    if command -v flake8 >/dev/null 2>&1 \
        && find . -path './.git' -prune -o -path './node_modules' -prune -o -name '*.py' -print -quit | grep -q .; then
        echo "flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics"
    fi
}

run_and_capture() {
    local command_value="$1" output_file status
    output_file=$(mktemp)
    bash -c "$command_value" >"$output_file" 2>&1
    status=$?
    cat "$output_file"
    if [ -n "$FAILURE_SIGNATURE_CMD" ]; then
        bash -c "$FAILURE_SIGNATURE_CMD" <"$output_file"
    else
        grep -E '^(FAILED|ERROR|FAIL|not ok|✕|AssertionError|.*(failed|error)[: ])' "$output_file" \
            | sed -E 's/[[:space:]]+[0-9]+(\.[0-9]+)?(ms|s|sec)[[:space:]]*$//' || true
    fi | tr -d '\r' | sed '/^[[:space:]]*$/d' | sort -u | while IFS= read -r line; do
        printf 'SIGNATURE:%s\n' "$line"
    done
    rm -f "$output_file"
    return "$status"
}

extract_bench_value() {
    awk 'NF { line = $0 } END {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
    }' | grep -E '^[-+]?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'
}

if [ -z "$STABLE_REF" ]; then
    echo "用法: ./scripts/capture_baseline.sh <stable-git-ref> [--allow-known-test-failures]" >&2
    exit 1
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "❌ 当前目录不是 Git 仓库；基线捕获需要可验证的稳定提交。" >&2
    exit 1
fi
if ! git rev-parse --verify "${STABLE_REF}^{commit}" >/dev/null 2>&1; then
    echo "❌ 稳定引用不存在: $STABLE_REF" >&2
    exit 1
fi
if [ ! -f "$CONTRACT_PATH" ]; then
    echo "❌ 缺少项目契约: $CONTRACT_PATH" >&2
    exit 1
fi
if ! [[ "$BENCH_THRESHOLD" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || ! awk -v threshold="$BENCH_THRESHOLD" 'BEGIN { exit !(threshold >= 0 && threshold <= 100) }'; then
    echo "❌ BENCH_THRESHOLD 必须是 0–100 之间的非负数，当前值: ${BENCH_THRESHOLD}" >&2
    exit 1
fi
case "$BENCH_HIGHER_IS_BETTER" in
    0|1) ;;
    *) echo "❌ BENCH_HIGHER_IS_BETTER 只能是 0 或 1，当前值: ${BENCH_HIGHER_IS_BETTER}" >&2; exit 1 ;;
esac
case "$PERF_CRITICAL" in
    0|1) ;;
    *) echo "❌ PERF_CRITICAL 只能是 0 或 1，当前值: ${PERF_CRITICAL}" >&2; exit 1 ;;
esac
CONTRACT_STATUS=$(sed -n 's/^contract_status:[[:space:]]*//p' "$CONTRACT_PATH" | head -n 1 | tr -d '"')
if [ "$CONTRACT_STATUS" != "CONFIRMED" ]; then
    echo "❌ 项目契约尚未 CONFIRMED: $CONTRACT_STATUS" >&2
    exit 1
fi
if grep -q '{{' "$CONTRACT_PATH"; then
    echo "❌ 项目契约仍有 {{...}} 占位符。" >&2
    exit 1
fi
if ! git ls-files --error-unmatch "$CONTRACT_PATH" >/dev/null 2>&1; then
    echo "❌ 项目契约尚未纳入 Git；先提交确认后的契约，再捕获基线。" >&2
    exit 1
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "❌ 工作区存在已跟踪文件的未提交改动；请在干净稳定版本上捕获基线。" >&2
    exit 1
fi
if [ -n "$(git ls-files --others --exclude-standard -- . ':(exclude).agents')" ]; then
    echo "❌ 工作区存在未跟踪的业务文件；它们会影响测试结果，不能作为可信基线。" >&2
    git ls-files --others --exclude-standard -- . ':(exclude).agents' | sed 's/^/    /' >&2
    exit 1
fi
BASELINE_SHA=$(git rev-parse HEAD)
STABLE_SHA=$(git rev-parse "${STABLE_REF}^{commit}")
if [ "$BASELINE_SHA" != "$STABLE_SHA" ]; then
    echo "❌ HEAD ($BASELINE_SHA) 与稳定引用 ($STABLE_SHA) 不一致；先检出用户认可的稳定版本。" >&2
    exit 1
fi
if git diff --quiet "$BASELINE_SHA" -- "$CONTRACT_PATH"; then
    :
else
    echo "❌ 契约有未提交改动；先提交确认后的契约再捕获基线。" >&2
    exit 1
fi

RESOLVED_TEST_CMD=$(detect_test_cmd)
RESOLVED_LINT_CMD=$(detect_lint_cmd)
mkdir -p "$(dirname "$BASELINE_DIR")"
STAGING_DIR=$(mktemp -d "${BASELINE_DIR}.staging.XXXXXX")
echo "🦺 正在以稳定提交 ${BASELINE_SHA:0:12} 捕获可信基线..."
for pair in "test:$RESOLVED_TEST_CMD" "core:$CORE_REGRESSION_CMD" "smoke:$SMOKE_CMD" "lint:$RESOLVED_LINT_CMD" "bench:$BENCH_CMD"; do
    label=${pair%%:*}
    command_value=${pair#*:}
    sha256_text "$command_value" >"${STAGING_DIR}/${label}.cmd"
done
sha256_text "$FAILURE_SIGNATURE_CMD" >"${STAGING_DIR}/signature.cmd"

if [ -z "$RESOLVED_TEST_CMD" ]; then
    echo "SIGNATURE:UNCONFIGURED_TEST_COMMAND" >"${STAGING_DIR}/test.signatures"
    TEST_STATUS=127
    echo "🟡 未配置 TEST_CMD；看门狗将把全量测试列入尚未验证。"
else
    TEST_OUTPUT=$(mktemp)
    run_and_capture "$RESOLVED_TEST_CMD" >"$TEST_OUTPUT" 2>&1
    TEST_STATUS=$?
    sed -n 's/^SIGNATURE://p' "$TEST_OUTPUT" >"${STAGING_DIR}/test.signatures"
    grep -v '^SIGNATURE:' "$TEST_OUTPUT" || true
    rm -f "$TEST_OUTPUT"
fi
if [ "$TEST_STATUS" != "0" ] && [ "$TEST_STATUS" != "127" ]; then
    if [ "$ALLOW_KNOWN_FAILURES" != "--allow-known-test-failures" ] || [ ! -s "${STAGING_DIR}/test.signatures" ]; then
        echo "BASELINE_FAILURE_UNCONFIRMED" >>"${STAGING_DIR}/test.signatures"
        echo "❌ 基线测试失败且未确认稳定失败签名；先修复基线或带 --allow-known-test-failures 并提供 FAILURE_SIGNATURE_CMD。" >&2
        exit 1
    fi
    echo "🟡 已记录 $(wc -l <"${STAGING_DIR}/test.signatures" | tr -d ' ') 条已知基线失败签名。"
fi

if [ -n "$CORE_REGRESSION_CMD" ]; then
    bash -c "$CORE_REGRESSION_CMD"; CORE_STATUS=$?
else
    CORE_STATUS=127
fi
if [ -n "$SMOKE_CMD" ]; then
    bash -c "$SMOKE_CMD"; SMOKE_STATUS=$?
else
    SMOKE_STATUS=127
fi
if [ -n "$RESOLVED_LINT_CMD" ]; then
    bash -c "$RESOLVED_LINT_CMD"; LINT_STATUS=$?
else
    LINT_STATUS=127
fi

BENCH_VALUE=""
if [ -n "$BENCH_CMD" ]; then
    BENCH_OUTPUT=$(mktemp)
    if bash -c "$BENCH_CMD" >"$BENCH_OUTPUT" 2>&1; then
        BENCH_VALUE=$(extract_bench_value <"$BENCH_OUTPUT")
        cat "$BENCH_OUTPUT"
    else
        cat "$BENCH_OUTPUT" >&2
        rm -f "$BENCH_OUTPUT"
        echo "❌ BENCH_CMD 在稳定基线上执行失败。" >&2
        exit 1
    fi
    rm -f "$BENCH_OUTPUT"
    if [ -z "$BENCH_VALUE" ]; then
        echo "❌ BENCH_CMD 的最后一行必须只输出一个数值。" >&2
        exit 1
    fi
    printf '%s\n' "$BENCH_VALUE" >"${STAGING_DIR}/bench.value"
else
    rm -f "${STAGING_DIR}/bench.value"
fi

if { [ "$CORE_STATUS" != "0" ] && [ "$CORE_STATUS" != "127" ]; } \
    || { [ "$SMOKE_STATUS" != "0" ] && [ "$SMOKE_STATUS" != "127" ]; } \
    || { [ "$LINT_STATUS" != "0" ] && [ "$LINT_STATUS" != "127" ]; }; then
    echo "❌ 基线中已配置的核心回归 / 冒烟 / 静态检查存在真实失败：core=$CORE_STATUS smoke=$SMOKE_STATUS lint=$LINT_STATUS" >&2
    exit 1
fi

CONTRACT_SHA256=$(sha256_file "$CONTRACT_PATH")
cat >"${STAGING_DIR}/manifest.env" <<EOF
BASELINE_SHA="${BASELINE_SHA}"
BASELINE_REF="${STABLE_REF}"
BASELINE_CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BASELINE_CONTRACT_SHA256="${CONTRACT_SHA256}"
BASELINE_TEST_STATUS="${TEST_STATUS}"
BASELINE_CORE_STATUS="${CORE_STATUS}"
BASELINE_SMOKE_STATUS="${SMOKE_STATUS}"
BASELINE_LINT_STATUS="${LINT_STATUS}"
BASELINE_BENCH_STATUS="$([ -n "$BENCH_VALUE" ] && echo 0 || echo 127)"
BASELINE_BENCH_THRESHOLD="${BENCH_THRESHOLD}"
BASELINE_HIGHER_IS_BETTER="${BENCH_HIGHER_IS_BETTER}"
BASELINE_PERF_CRITICAL="${PERF_CRITICAL}"
EOF
printf '%s\n' "$(evidence_digest "$STAGING_DIR")" >"${STAGING_DIR}/evidence.sha256"
if [ -d "$BASELINE_DIR" ]; then
    PREVIOUS_DIR="${BASELINE_DIR}.previous.$$"
    mv "$BASELINE_DIR" "$PREVIOUS_DIR"
fi
if ! mv "$STAGING_DIR" "$BASELINE_DIR"; then
    echo "❌ 无法启用新基线；上一份有效基线将自动恢复。" >&2
    exit 1
fi
STAGING_DIR=""
rm -rf "$PREVIOUS_DIR"
PREVIOUS_DIR=""
trap - EXIT
echo "✅ 可信基线已写入 ${BASELINE_DIR}/manifest.env"
echo "ℹ️  缺失的全量测试、核心回归、冒烟、静态或性能命令会进入看门狗尚未验证清单；只有显式豁免才能得到 PARTIAL。"
