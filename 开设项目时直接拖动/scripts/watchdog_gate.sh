#!/usr/bin/env bash
# ==============================================================================
# 看门狗独立门禁: scripts/watchdog_gate.sh
# 适用范围: 计划工作流 / 程序修复工作流 / UI 工作流共用
# 退出码:
#   - 0   : 已验证项全绿；显式豁免时使用 PARTIAL 结论
#   - 101 : 目标复现 / 新增 AC 仍失败
#   - 102 : 全量测试出现新增失败
#   - 103 : 性能或资源指标相对可信基线劣化超阈值
#   - 104 : 防作弊或证据篡改审计失败
#   - 105 : 静态 / 类型检查失败
#   - 106 : 契约、基线或证据配置不足
#   - 107 : 基线本身不稳定且没有已确认的失败签名
#   - 108 : 冒烟或核心链路回归失败
# ==============================================================================
set -uo pipefail

REPRO_TARGET="${1:-}"
BASE_REF_ARG="${2:-}"

TEST_CMD=""
LINT_CMD=""
BENCH_CMD=""
CORE_REGRESSION_CMD=""
SMOKE_CMD=""
FAILURE_SIGNATURE_CMD=""
TEST_DIR="tests"
BASE_TAG=""
CONTRACT_PATH=".agents/PROJECT_CONTRACT.md"
BENCH_THRESHOLD="${BENCH_THRESHOLD:-3}"
BENCH_HIGHER_IS_BETTER="${BENCH_HIGHER_IS_BETTER:-0}"
PERF_CRITICAL="${PERF_CRITICAL:-0}"
ALLOW_TEST_EDIT="${ALLOW_TEST_EDIT:-0}"
ALLOW_UNVERIFIED="${ALLOW_UNVERIFIED:-0}"
BASELINE_DIR=".agents/baseline"
UNVERIFIED=()
BASELINE_FAILURE_SIGNATURE=""
export PYTHONPATH="${PYTHONPATH:-.}"

if [ -f ".agents/workflow.config" ]; then
    # shellcheck disable=SC1091
    if ! source ".agents/workflow.config"; then
        echo "❌ [106] 本地证据配置无法加载: .agents/workflow.config"
        exit 106
    fi
fi

if [ -n "$BASE_REF_ARG" ]; then
    BASE_TAG="$BASE_REF_ARG"
elif [ -z "$BASE_TAG" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BASE_TAG=$(git tag -l "pre-fix-*" "pre-feature-*" | tail -n 1 || echo "")
fi

detect_test_cmd() {
    if [ -n "$TEST_CMD" ]; then
        echo "$TEST_CMD"
    elif [ -f "package.json" ]; then
        echo "npm test --silent"
    elif [ -f "Cargo.toml" ]; then
        echo "cargo test --quiet"
    elif [ -f "go.mod" ]; then
        echo "go test ./..."
    elif [ -f "pyproject.toml" ] || [ -f "pytest.ini" ] || [ -f "requirements.txt" ] || [ -f "setup.py" ] \
        || { [ -d "$TEST_DIR" ] && find "$TEST_DIR" -maxdepth 2 -name '*.py' -print -quit | grep -q .; }; then
        if command -v pytest >/dev/null 2>&1; then
            echo "pytest -q"
        else
            echo "python3 -m unittest discover -s ${TEST_DIR}"
        fi
    fi
}

detect_lint_cmd() {
    if [ -n "$LINT_CMD" ]; then
        echo "$LINT_CMD"
    elif command -v flake8 >/dev/null 2>&1 \
        && find . -path './.git' -prune -o -path './node_modules' -prune -o -name '*.py' -print -quit | grep -q .; then
        echo "flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics"
    fi
}

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

read_front_matter_value() {
    local key="$1"
    sed -n "s/^${key}:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" "$CONTRACT_PATH" | head -n 1
}

command_checksum() {
    local label="$1" command_value="$2" baseline_value current_value
    baseline_value=$(cat "${BASELINE_DIR}/${label}.cmd" 2>/dev/null || true)
    current_value=$(sha256_text "$command_value")
    [ "$baseline_value" = "$current_value" ]
}

run_and_capture() {
    local label="$1" command_value="$2" output_file status
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

extract_signatures() {
    sed -n 's/^SIGNATURE://p'
}

extract_bench_value() {
    awk 'NF { line = $0 } END {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
    }' | grep -E '^[-+]?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'
}

is_performance_regression() {
    awk -v base="$1" -v current="$2" -v threshold="$3" -v higher="$4" 'BEGIN {
        if (higher == 1) {
            allowed = base * (1 - threshold / 100)
            exit (current < allowed) ? 0 : 1
        }
        allowed = base * (1 + threshold / 100)
        exit (current > allowed) ? 0 : 1
    }'
}

record_unverified() {
    UNVERIFIED+=("$1")
    echo "⚠️  [未验证] $1"
}

fail() {
    local code="$1"
    shift
    echo "❌ [$code] $*"
    exit "$code"
}

echo "🐕 ==========================================================="
echo "   [看门狗 Watchdog] 项目契约 + 可信基线 + 五道证据门禁"
echo "==========================================================="

# ------------------------------------------------------------------------------
# 门禁 0: 项目契约与基线证据 (Exit 106 / 107)
# ------------------------------------------------------------------------------
echo "🔍 [门禁 0] 读取项目契约、基线记录与证据命令..."
if [ ! -f "$CONTRACT_PATH" ]; then
    fail 106 "缺少 ${CONTRACT_PATH}；先执行项目适配与契约初始化工作流。"
fi
CONTRACT_STATUS=$(read_front_matter_value "contract_status")
if [ "$CONTRACT_STATUS" != "CONFIRMED" ]; then
    fail 106 "项目契约状态为 ${CONTRACT_STATUS:-空}，未由用户确认。"
fi
if grep -q '{{' "$CONTRACT_PATH"; then
    fail 106 "项目契约仍存在 {{...}} 占位符。"
fi
if [ ! -f "${BASELINE_DIR}/manifest.env" ]; then
    fail 106 "缺少可信基线；动工前先运行 ./scripts/capture_baseline.sh <stable-ref>。"
fi
EXPECTED_EVIDENCE_DIGEST=$(cat "${BASELINE_DIR}/evidence.sha256" 2>/dev/null || true)
if [ -z "$EXPECTED_EVIDENCE_DIGEST" ]; then
    fail 106 "缺少基线证据摘要；重新运行 capture_baseline.sh。"
fi
if [ "$(evidence_digest "$BASELINE_DIR")" != "$EXPECTED_EVIDENCE_DIGEST" ]; then
    fail 104 "可信基线的清单、失败签名或性能数值被修改；重新捕获基线。"
fi
# shellcheck disable=SC1091
source "${BASELINE_DIR}/manifest.env" || fail 106 "基线清单不可读。"
if [ ! -f "${BASELINE_DIR}/signature.cmd" ]; then
    fail 106 "基线缺少失败签名命令记录；重新运行 capture_baseline.sh。"
fi
if [ "$(sha256_file "$CONTRACT_PATH")" != "${BASELINE_CONTRACT_SHA256:-}" ]; then
    fail 104 "项目契约相对可信基线已改变；确认修订并重新捕获基线后才能继续。"
fi
if ! [[ "$BENCH_THRESHOLD" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || ! awk -v threshold="$BENCH_THRESHOLD" 'BEGIN { exit !(threshold >= 0 && threshold <= 100) }'; then
    fail 106 "BENCH_THRESHOLD 必须是 0–100 之间的非负数，当前值: ${BENCH_THRESHOLD}"
fi
case "$BENCH_HIGHER_IS_BETTER" in
    0|1) ;;
    *) fail 106 "BENCH_HIGHER_IS_BETTER 只能是 0 或 1。" ;;
esac
case "$PERF_CRITICAL" in
    0|1) ;;
    *) fail 106 "PERF_CRITICAL 只能是 0 或 1。" ;;
esac
if [ "$BENCH_THRESHOLD" != "${BASELINE_BENCH_THRESHOLD:-}" ] \
    || [ "$BENCH_HIGHER_IS_BETTER" != "${BASELINE_HIGHER_IS_BETTER:-}" ] \
    || [ "$PERF_CRITICAL" != "${BASELINE_PERF_CRITICAL:-}" ]; then
    fail 106 "性能阈值、方向或关键性开关相对基线已改变；重新捕获基线。"
fi

RESOLVED_TEST_CMD=$(detect_test_cmd)
RESOLVED_LINT_CMD=$(detect_lint_cmd)
for record in test core smoke lint bench signature; do
    case "$record" in
        test) resolved="$RESOLVED_TEST_CMD" ;;
        core) resolved="$CORE_REGRESSION_CMD" ;;
        smoke) resolved="$SMOKE_CMD" ;;
        lint) resolved="$RESOLVED_LINT_CMD" ;;
        bench) resolved="$BENCH_CMD" ;;
        signature) resolved="$FAILURE_SIGNATURE_CMD" ;;
    esac
    if ! command_checksum "$record" "$resolved"; then
        fail 106 "${record} 证据命令相对基线已改变；重新运行 capture_baseline.sh。"
    fi
done

BASELINE_FAILURE_SIGNATURE=$(cat "${BASELINE_DIR}/test.signatures" 2>/dev/null || true)
if [ "$BASELINE_TEST_STATUS" != "0" ] && [ "$BASELINE_TEST_STATUS" != "127" ]; then
    if [ -z "$BASELINE_FAILURE_SIGNATURE" ] || grep -q 'BASELINE_FAILURE_UNCONFIRMED' "${BASELINE_DIR}/test.signatures"; then
        fail 107 "基线测试原本失败且没有已确认的稳定失败签名。"
    fi
    echo "🟡 [基线提示] 允许已确认的基线失败签名，仅检查是否出现新增失败。"
fi
for baseline_status in "$BASELINE_CORE_STATUS" "$BASELINE_SMOKE_STATUS" "$BASELINE_LINT_STATUS"; do
    if [ "$baseline_status" != "0" ] && [ "$baseline_status" != "127" ]; then
        fail 107 "基线的核心回归、冒烟或静态检查存在真实失败；先修复基线再修改业务代码。"
    fi
done
echo "✅ [门禁 0 通过] 契约已确认，基线 SHA ${BASELINE_SHA:-未知} 与证据命令一致。"

# ------------------------------------------------------------------------------
# 门禁 1: 目标复现 / 新增 AC (Exit 101)
# ------------------------------------------------------------------------------
echo "🔍 [门禁 1/5] 验证目标复现脚本 / AC 断言..."
if [ -z "$REPRO_TARGET" ]; then
    record_unverified "未指定单独复现脚本或新增 AC 测试。"
else
    run_repro_target() {
        local target="$1"
        if [ ! -f "$target" ]; then
            bash -c "$target"
            return $?
        fi
        case "$target" in
            *.py)
                if command -v pytest >/dev/null 2>&1 && [[ "$(basename "$target")" == test_* ]]; then
                    pytest -q "$target"
                else
                    python3 "$target"
                fi
                ;;
            *.sh) bash "$target" ;;
            *.js|*.mjs) node "$target" ;;
            *.spec.ts|*.test.ts) npx playwright test "$target" ;;
            *) "$target" ;;
        esac
    }
    if run_repro_target "$REPRO_TARGET"; then
        echo "✅ [门禁 1 通过] 目标复现已转绿。"
    else
        fail 101 "目标复现或新增 AC 测试仍失败。"
    fi
fi

# ------------------------------------------------------------------------------
# 门禁 2: 防作弊与证据篡改审计 (Exit 104)
# ------------------------------------------------------------------------------
echo "🔍 [门禁 2/5] 执行防作弊与证据篡改审计..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -n "$BASE_TAG" ] && git rev-parse --verify "${BASE_TAG}^{commit}" >/dev/null 2>&1; then
    if [ "$ALLOW_TEST_EDIT" != "1" ] && [ -d "$TEST_DIR" ]; then
        TAMPERED_TESTS=$(git diff --name-status --find-renames "${BASE_TAG}" -- "$TEST_DIR" \
            | awk '$1 ~ /^(M|D|R|C|T)/ {print $2}' || true)
        if [ -n "$REPRO_TARGET" ] && git cat-file -e "${BASE_TAG}:${REPRO_TARGET}" 2>/dev/null; then
            # A reproduction path present at the baseline is an existing test, not a new waiver.
            :
        elif [ -n "$REPRO_TARGET" ]; then
            TAMPERED_TESTS=$(echo "$TAMPERED_TESTS" | grep -v -F "$REPRO_TARGET" || true)
        fi
        if [ -n "$TAMPERED_TESTS" ]; then
            echo "$TAMPERED_TESTS" | sed 's/^/    - /'
            fail 104 "检测到未经授权修改或删除既有测试文件。"
        fi
    fi
    TAMPERED_EVIDENCE=$(git diff --name-status "${BASE_TAG}" -- "$CONTRACT_PATH" "${BASELINE_DIR}" ".agents/workflow.config" \
        | awk '$1 ~ /^[MD]/ {print $2}' || true)
    if [ -n "$TAMPERED_EVIDENCE" ]; then
        echo "$TAMPERED_EVIDENCE" | sed 's/^/    /'
        fail 104 "检测到契约、基线证据或证据配置被修改；必须重新确认并捕获基线。"
    fi
    CHEAT_PATTERNS='(\.skip\(|@pytest\.mark\.skip|@pytest\.mark\.xfail|@unittest\.skip|\.only\(|sys\.exit\(0\)|os\._exit\(0\))'
    DIFF_ADDED=$(git diff "${BASE_TAG}" -- "$TEST_DIR" | grep -E '^\+[^+]' || true)
    CHEAT_HITS=$(echo "$DIFF_ADDED" | grep -E "$CHEAT_PATTERNS" || true)
    if [ -n "$CHEAT_HITS" ]; then
        echo "$CHEAT_HITS" | head -n 5 | sed 's/^/    /'
        fail 104 "检测到疑似跳过测试或强制绿灯的逃逸指令。"
    fi
    echo "✅ [门禁 2 通过] 未发现测试、契约或基线证据篡改 (基线: ${BASE_TAG})。"
else
    record_unverified "缺少 Git 基线标签，无法执行 Diff 防作弊比对。"
fi

# ------------------------------------------------------------------------------
# 门禁 3: 全量测试只允许已确认的基线失败 (Exit 102)
# ------------------------------------------------------------------------------
echo "🔍 [门禁 3/5] 检查全量测试相对基线的失败签名..."
if [ -z "$RESOLVED_TEST_CMD" ]; then
    record_unverified "未配置 TEST_CMD，全量历史测试未验证。"
else
    TEST_OUTPUT=$(mktemp)
    run_and_capture "test" "$RESOLVED_TEST_CMD" >"$TEST_OUTPUT" 2>&1
    TEST_STATUS=$?
    CURRENT_FAILURE_SIGNATURE=$(extract_signatures <"$TEST_OUTPUT")
    if [ "$TEST_STATUS" != "0" ] && [ -z "$CURRENT_FAILURE_SIGNATURE" ]; then
        printf 'SIGNATURE:UNCLASSIFIED_TEST_FAILURE_%s\n' "$TEST_STATUS" >>"$TEST_OUTPUT"
        CURRENT_FAILURE_SIGNATURE=$(extract_signatures <"$TEST_OUTPUT")
    fi
    NEW_FAILURES=$(comm -13 <(printf '%s\n' "$BASELINE_FAILURE_SIGNATURE") <(printf '%s\n' "$CURRENT_FAILURE_SIGNATURE"))
    rm -f "$TEST_OUTPUT"
    if [ -n "$NEW_FAILURES" ]; then
        echo "$NEW_FAILURES" | sed 's/^/    - /'
        fail 102 "全量测试出现相对基线的新增失败。"
    fi
    if [ "$TEST_STATUS" != "0" ]; then
        echo "🟡 [门禁 3 提示] 仅存在已确认的基线失败："
        printf '%s\n' "$BASELINE_FAILURE_SIGNATURE" | sed '/^[[:space:]]*$/d; s/^/    /'
    else
        echo "✅ [门禁 3 通过] 全量测试绿灯，零新增失败。"
    fi
fi

# ------------------------------------------------------------------------------
# 门禁 4: 核心链路、冒烟与性能数值对照 (Exit 108 / 103)
# ------------------------------------------------------------------------------
echo "🔍 [门禁 4/5] 运行核心链路、冒烟与性能证据..."
if [ -z "$CORE_REGRESSION_CMD" ]; then
    record_unverified "未配置 CORE_REGRESSION_CMD。"
elif ! bash -c "$CORE_REGRESSION_CMD"; then
    fail 108 "核心链路回归失败。"
else
    echo "✅ [门禁 4a 通过] 核心链路回归通过。"
fi
if [ -z "$SMOKE_CMD" ]; then
    record_unverified "未配置 SMOKE_CMD。"
elif ! bash -c "$SMOKE_CMD"; then
    fail 108 "端到端冒烟失败。"
else
    echo "✅ [门禁 4b 通过] 端到端冒烟通过。"
fi
if [ -z "$BENCH_CMD" ]; then
    if [ "$PERF_CRITICAL" = "1" ]; then
        fail 103 "项目契约声明性能关键，但 BENCH_CMD 未配置，不能宣称性能达标。"
    fi
    record_unverified "未配置 BENCH_CMD，性能未做数值对照。"
else
    BENCH_OUTPUT=$(mktemp)
    if ! bash -c "$BENCH_CMD" >"$BENCH_OUTPUT" 2>&1; then
        cat "$BENCH_OUTPUT"
        rm -f "$BENCH_OUTPUT"
        fail 103 "BENCH_CMD 执行失败。"
    fi
    CURRENT_BENCH_VALUE=$(extract_bench_value <"$BENCH_OUTPUT")
    rm -f "$BENCH_OUTPUT"
    BASELINE_BENCH_VALUE=$(cat "${BASELINE_DIR}/bench.value" 2>/dev/null || true)
    if [ -z "$CURRENT_BENCH_VALUE" ] || [ -z "$BASELINE_BENCH_VALUE" ]; then
        fail 103 "BENCH_CMD 必须让最后一行只输出一个数值，且基线数值必须存在。"
    fi
    if is_performance_regression "$BASELINE_BENCH_VALUE" "$CURRENT_BENCH_VALUE" "$BENCH_THRESHOLD" "$BENCH_HIGHER_IS_BETTER"; then
        echo "    baseline=${BASELINE_BENCH_VALUE} current=${CURRENT_BENCH_VALUE} threshold=${BENCH_THRESHOLD}%"
        fail 103 "性能或资源指标相对可信基线劣化超阈值。"
    fi
    echo "✅ [门禁 4c 通过] baseline=${BASELINE_BENCH_VALUE} current=${CURRENT_BENCH_VALUE}，阈值 ${BENCH_THRESHOLD}%。"
fi

# ------------------------------------------------------------------------------
# 门禁 5: 静态与类型安全 (Exit 105)
# ------------------------------------------------------------------------------
echo "🔍 [门禁 5/5] 运行静态语法与类型检查..."
if [ -z "$RESOLVED_LINT_CMD" ]; then
    record_unverified "未配置 LINT_CMD，静态检查未验证。"
elif ! bash -c "$RESOLVED_LINT_CMD"; then
    fail 105 "静态或类型安全检查未通过。"
else
    echo "✅ [门禁 5 通过] 静态检查通过 (${RESOLVED_LINT_CMD})。"
fi

echo "---------------------------------------------------------------------------"
if [ "${#UNVERIFIED[@]}" -gt 0 ]; then
    echo "📋 尚未验证清单："
    printf '    - %s\n' "${UNVERIFIED[@]}"
    if [ "$ALLOW_UNVERIFIED" != "1" ]; then
        fail 106 "存在未验证项目证据。须补齐证据；确需豁免时由用户设置 ALLOW_UNVERIFIED=1 并记录 ADR。"
    fi
    echo "🏆 ==========================================================="
    echo "   [看门狗结论 PARTIAL] 已验证项通过；豁免项已在上方列明。"
    echo "   交付报告必须列出：已修复 / 保持不变 / 尚未验证 / 已拒绝建议及理由。"
    echo "==========================================================="
    exit 0
fi
echo "🏆 ==========================================================="
echo "   [看门狗结论 PASS] 已验证项全绿；不含未验证豁免项。"
echo "   交付报告仍必须列出：已修复 / 保持不变 / 尚未验证 / 已拒绝建议及理由。"
echo "==========================================================="
exit 0
