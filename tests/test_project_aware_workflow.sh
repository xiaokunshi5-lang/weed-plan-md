#!/usr/bin/env bash
# Isolated regression tests for the project-contract and evidence gates.
# All fixtures are created in a temporary directory; the workflow pack is read-only.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKFLOW_PACK=$(dirname "$SCRIPT_DIR")
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/workflow-gate-test.XXXXXX")
LAST_OUTPUT="${TMP_ROOT}/last-output.log"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0

expect_status() {
    local expected="$1" label="$2"
    shift 2
    local status=0
    "$@" >"$LAST_OUTPUT" 2>&1 || status=$?
    if [ "$status" -ne "$expected" ]; then
        echo "FAIL: ${label} (expected ${expected}, got ${status})" >&2
        sed 's/^/    /' "$LAST_OUTPUT" >&2
        exit 1
    fi
    pass_count=$((pass_count + 1))
    echo "PASS: ${label}"
}

expect_last_output() {
    local needle="$1" label="$2"
    if ! grep -qF "$needle" "$LAST_OUTPUT"; then
        echo "FAIL: ${label} (missing output: ${needle})" >&2
        sed 's/^/    /' "$LAST_OUTPUT" >&2
        exit 1
    fi
    pass_count=$((pass_count + 1))
    echo "PASS: ${label}"
}

prepare_contract() {
    WORKFLOW_PACK_DIR="$WORKFLOW_PACK" "$WORKFLOW_PACK/scripts/init_project_contract.sh" >/dev/null
    perl -0pi -e '
        s/contract_status: DRAFT/contract_status: CONFIRMED/;
        s/confirmed_at: ""/confirmed_at: "2026-11-07"/;
        s/confirmed_by: ""/confirmed_by: "automated-test"/;
        s/\{\{[^}]*\}\}/confirmed/g;
    ' .agents/PROJECT_CONTRACT.md
}

setup_project() {
    local root="$1" test_mode="$2" bench_mode="$3" perf_critical="$4"
    local bench_cmd="bash tests/bench.sh"
    mkdir -p "$root"
    cd "$root"
    git init -q
    git config user.name "Workflow Test"
    git config user.email "workflow-test@example.com"
    prepare_contract
    mkdir -p tests

    cat > tests/repro.sh <<'EOF'
#!/usr/bin/env bash
echo "target reproduction is green"
exit 0
EOF
    cat > tests/test_all_pass.sh <<'EOF'
#!/usr/bin/env bash
echo "all tests passed"
exit 0
EOF
    cat > tests/test_all_knownfail.sh <<'EOF'
#!/usr/bin/env bash
echo "FAILED: stable known issue"
exit 1
EOF
    for name in core smoke lint; do
        cat > "tests/${name}.sh" <<EOF
#!/usr/bin/env bash
echo "${name} passed"
exit 0
EOF
    done
    cat > tests/bench.sh <<'EOF'
#!/usr/bin/env bash
cat bench.value
EOF
    printf '100\n' > bench.value
    chmod +x tests/*.sh

    if [ "$bench_mode" = "none" ]; then
        bench_cmd=""
    fi
    cat > .agents/workflow.config <<EOF
CONTRACT_PATH=".agents/PROJECT_CONTRACT.md"
TEST_DIR="tests"
TEST_CMD="bash tests/test_all_${test_mode}.sh"
CORE_REGRESSION_CMD="bash tests/core.sh"
SMOKE_CMD="bash tests/smoke.sh"
LINT_CMD="bash tests/lint.sh"
BENCH_CMD="${bench_cmd}"
BENCH_THRESHOLD="3"
BENCH_HIGHER_IS_BETTER="0"
PERF_CRITICAL="${perf_critical}"
EOF

    git add -A
    git commit -q -m "baseline fixtures"
    git tag pre-feature-stable
}

echo "== Static checks =="
bash -n "$WORKFLOW_PACK"/scripts/*.sh
node --check "$WORKFLOW_PACK/scripts/ui_tactile_kit.js"
for doc in \
    "README.md" \
    "计划工作流.md" \
    "程序修复工作流.md" \
    "UI审美与开源组件借鉴工作流.md" \
    "项目适配与契约初始化工作流.md" \
    "项目契约模板.md" \
    "工作流完善调研与实施计划.md"; do
    [ -f "${WORKFLOW_PACK}/${doc}" ] || { echo "FAIL: missing ${doc}" >&2; exit 1; }
done
echo "PASS: shell syntax, JS syntax, and linked core documents"

echo "== Missing contract and DRAFT gates =="
MISSING_DIR="${TMP_ROOT}/missing"
mkdir -p "$MISSING_DIR"
cd "$MISSING_DIR"
printf '# Existing Agent Rules\n\nKeep this file.\n' > AGENTS.md
cp AGENTS.md "${TMP_ROOT}/agents.before"
WORKFLOW_PACK_DIR="$WORKFLOW_PACK" "$WORKFLOW_PACK/scripts/init_project_contract.sh" >/dev/null
[ -f .agents/PROJECT_CONTRACT.md ] || { echo "FAIL: DRAFT contract was not created" >&2; exit 1; }
[ -f .agents/workflow.config ] || { echo "FAIL: local workflow config was not created" >&2; exit 1; }
cp .agents/PROJECT_CONTRACT.md "${TMP_ROOT}/draft.before"
cp .agents/workflow.config "${TMP_ROOT}/config.before"
WORKFLOW_PACK_DIR="$WORKFLOW_PACK" "$WORKFLOW_PACK/scripts/init_project_contract.sh" >/dev/null
cmp -s .agents/PROJECT_CONTRACT.md "${TMP_ROOT}/draft.before" \
    || { echo "FAIL: init script overwrote an existing contract" >&2; exit 1; }
cmp -s .agents/workflow.config "${TMP_ROOT}/config.before" \
    || { echo "FAIL: init script overwrote an existing workflow config" >&2; exit 1; }
cmp -s AGENTS.md "${TMP_ROOT}/agents.before" \
    || { echo "FAIL: init script modified an existing AGENTS.md" >&2; exit 1; }
expect_status 106 "watchdog rejects DRAFT contract" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
expect_status 200 "fix attempt rejects DRAFT contract" \
    "$WORKFLOW_PACK/scripts/fix_attempt.sh" 1 "hypothesis"
expect_status 1 "baseline capture rejects non-Git workspace" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" stable
echo "PASS: init script is idempotent"

echo "== Healthy baseline and evidence gates =="
MAIN_DIR="${TMP_ROOT}/main"
setup_project "$MAIN_DIR" pass normal 1
expect_status 0 "capture trusted baseline" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable
expect_status 0 "all evidence gates pass" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
expect_last_output "PASS" "healthy report is PASS, not PARTIAL"

cp .agents/PROJECT_CONTRACT.md "${TMP_ROOT}/contract-hash.bak"
printf '\n# changed after baseline\n' >> .agents/PROJECT_CONTRACT.md
expect_status 104 "contract hash change is rejected before test diff audit" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
expect_status 200 "fix attempt rejects a contract changed after baseline" \
    "$WORKFLOW_PACK/scripts/fix_attempt.sh" 2 "must not run with stale evidence"
mv "${TMP_ROOT}/contract-hash.bak" .agents/PROJECT_CONTRACT.md

printf '200\n' > bench.value
expect_status 103 "performance regression is rejected" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
printf '100\n' > bench.value

cp .agents/workflow.config "${TMP_ROOT}/workflow.config.bak"
perl -0pi -e 's/BENCH_CMD="bash tests\/bench.sh"/BENCH_CMD="bash tests\/bench_alt.sh"/' .agents/workflow.config
expect_status 106 "changed evidence command requires a new baseline" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
mv "${TMP_ROOT}/workflow.config.bak" .agents/workflow.config

cp .agents/workflow.config "${TMP_ROOT}/threshold.config.bak"
perl -0pi -e 's/BENCH_THRESHOLD="3"/BENCH_THRESHOLD="30"/' .agents/workflow.config
expect_status 106 "relaxed performance threshold requires a new baseline" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
mv "${TMP_ROOT}/threshold.config.bak" .agents/workflow.config

cp .agents/workflow.config "${TMP_ROOT}/signature.config.bak"
printf '\nFAILURE_SIGNATURE_CMD="grep -E FAILED"\n' >> .agents/workflow.config
expect_status 106 "changed failure signature command requires a new baseline" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
mv "${TMP_ROOT}/signature.config.bak" .agents/workflow.config

cp .agents/PROJECT_CONTRACT.md "${TMP_ROOT}/contract.bak"
printf '\n# tampered after baseline\n' >> .agents/PROJECT_CONTRACT.md
expect_status 104 "contract tampering is rejected" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
mv "${TMP_ROOT}/contract.bak" .agents/PROJECT_CONTRACT.md

cp .agents/baseline/test.signatures "${TMP_ROOT}/test.signatures.bak"
printf 'SIGNATURE:injected_baseline_failure\n' >> .agents/baseline/test.signatures
expect_status 104 "baseline evidence tampering is rejected" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
mv "${TMP_ROOT}/test.signatures.bak" .agents/baseline/test.signatures

expect_status 0 "fix attempt accepts confirmed contract and baseline" \
    "$WORKFLOW_PACK/scripts/fix_attempt.sh" 1 "single verified hypothesis"

cp tests/repro.sh "${TMP_ROOT}/existing-repro.bak"
printf '\n# weakened existing reproduction\n' >> tests/repro.sh
expect_status 104 "existing reproduction test cannot exempt itself from tamper audit" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
mv "${TMP_ROOT}/existing-repro.bak" tests/repro.sh

cat > tests/new_repro.sh <<'EOF'
#!/usr/bin/env bash
echo "new reproduction is green"
exit 0
EOF
chmod +x tests/new_repro.sh
expect_status 0 "newly added reproduction test is accepted" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/new_repro.sh pre-feature-stable

echo "== Known baseline failures and explicit waivers =="
KNOWN_DIR="${TMP_ROOT}/known-failure"
setup_project "$KNOWN_DIR" knownfail normal 0
expect_status 0 "known baseline failure can be captured" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable --allow-known-test-failures
expect_status 0 "known baseline failure is not a new regression" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
expect_last_output "已确认的基线失败" "known failure is reported transparently"

UNKNOWN_DIR="${TMP_ROOT}/unknown-failure"
setup_project "$UNKNOWN_DIR" knownfail normal 0
expect_status 1 "unconfirmed baseline failure is rejected" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable

UNVERIFIED_DIR="${TMP_ROOT}/unverified"
setup_project "$UNVERIFIED_DIR" pass none 0
expect_status 0 "capture baseline without a performance command" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable
expect_status 106 "unverified evidence blocks PASS by default" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
expect_status 0 "explicit waiver allows PARTIAL" \
    env ALLOW_UNVERIFIED=1 "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
expect_last_output "PARTIAL" "waiver output is marked PARTIAL"

PERF_DIR="${TMP_ROOT}/perf-critical"
setup_project "$PERF_DIR" pass none 1
expect_status 0 "capture baseline with PERF_CRITICAL and no bench command" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable
expect_status 103 "PERF_CRITICAL requires a numeric performance command" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable

HIGHER_DIR="${TMP_ROOT}/higher-is-better"
setup_project "$HIGHER_DIR" pass normal 0
perl -0pi -e 's/BENCH_HIGHER_IS_BETTER="0"/BENCH_HIGHER_IS_BETTER="1"/' .agents/workflow.config
expect_status 0 "capture higher-is-better baseline" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable
printf '80\n' > bench.value
expect_status 103 "throughput drop is rejected" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
printf '120\n' > bench.value
expect_status 0 "throughput improvement passes" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable

echo "== Baseline integrity, missing commands, and command format =="
MISSING_EVIDENCE_DIR="${TMP_ROOT}/missing-evidence"
setup_project "$MISSING_EVIDENCE_DIR" pass normal 0
perl -0pi -e '
    s/CORE_REGRESSION_CMD="[^"]*"/CORE_REGRESSION_CMD=""/;
    s/SMOKE_CMD="[^"]*"/SMOKE_CMD=""/;
    s/LINT_CMD="[^"]*"/LINT_CMD=""/;
' .agents/workflow.config
expect_status 0 "baseline can record missing core, smoke, and lint evidence" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable
expect_status 106 "missing baseline evidence cannot produce PASS" \
    "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
expect_status 0 "missing baseline evidence can produce PARTIAL by explicit waiver" \
    env ALLOW_UNVERIFIED=1 "$WORKFLOW_PACK/scripts/watchdog_gate.sh" tests/repro.sh pre-feature-stable
expect_last_output "PARTIAL" "missing evidence waiver is marked PARTIAL"

UNTRACKED_DIR="${TMP_ROOT}/untracked-business-file"
setup_project "$UNTRACKED_DIR" pass normal 0
printf 'runtime override\n' > untracked.config
expect_status 1 "untracked business files cannot contaminate a baseline" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable

UNTRACKED_CONTRACT_DIR="${TMP_ROOT}/untracked-contract"
setup_project "$UNTRACKED_CONTRACT_DIR" pass normal 0
git rm --cached -q .agents/PROJECT_CONTRACT.md
git commit -q -m "remove contract from version control"
expect_status 1 "contract must be tracked before it can anchor a baseline" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable

ATOMIC_DIR="${TMP_ROOT}/atomic-baseline"
setup_project "$ATOMIC_DIR" pass normal 0
expect_status 0 "capture baseline before a failed recapture" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-stable
ORIGINAL_MANIFEST=$(cat .agents/baseline/manifest.env)
cat > tests/core.sh <<'EOF'
#!/usr/bin/env bash
echo "core failed"
exit 1
EOF
chmod +x tests/core.sh
git add tests/core.sh
git commit -q -m "break core for atomic baseline test"
git tag -f pre-feature-bad >/dev/null
expect_status 1 "failed baseline capture is rejected" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-bad
[ "$(cat .agents/baseline/manifest.env)" = "$ORIGINAL_MANIFEST" ] \
    || { echo "FAIL: failed capture replaced the previous trusted baseline" >&2; exit 1; }
echo "PASS: failed capture preserves the previous trusted baseline"
pass_count=$((pass_count + 1))

BENCH_FORMAT_DIR="${TMP_ROOT}/bench-format"
setup_project "$BENCH_FORMAT_DIR" pass normal 0
cat > tests/bench.sh <<'EOF'
#!/usr/bin/env bash
printf '100\nfinished\n'
EOF
chmod +x tests/bench.sh
git add tests/bench.sh
git commit -q -m "benchmark output with trailing log"
git tag -f pre-feature-bench-format >/dev/null
expect_status 1 "benchmark must end with the numeric metric" \
    "$WORKFLOW_PACK/scripts/capture_baseline.sh" pre-feature-bench-format

ROLLBACK_DIR="${TMP_ROOT}/non-git-rollback"
mkdir -p "${ROLLBACK_DIR}/.agents/snapshots/stable"
cd "$ROLLBACK_DIR"
printf 'stable snapshot\n' > .agents/snapshots/stable/content.txt
printf 'current workspace\n' > content.txt
expect_status 0 "non-Git rollback dry-run succeeds" \
    "$WORKFLOW_PACK/scripts/rollback.sh" stable --dry-run
[ "$(cat content.txt)" = "current workspace" ] \
    || { echo "FAIL: rollback dry-run modified the non-Git workspace" >&2; exit 1; }
expect_status 0 "non-Git snapshot rollback succeeds" \
    "$WORKFLOW_PACK/scripts/rollback.sh" stable
[ "$(cat content.txt)" = "stable snapshot" ] \
    || { echo "FAIL: non-Git snapshot rollback did not restore content" >&2; exit 1; }
echo "PASS: non-Git rollback dry-run is read-only and restore works"
pass_count=$((pass_count + 1))

echo "ALL PASS: ${pass_count} assertions"
