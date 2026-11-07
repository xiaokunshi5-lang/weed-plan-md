#!/usr/bin/env bash
# 在目标项目内创建一个可版本管理的项目契约目录，不覆盖已有文件。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORKFLOW_PACK="${WORKFLOW_PACK_DIR:-$(dirname "$SCRIPT_DIR")}"
TEMPLATE="${WORKFLOW_PACK}/项目契约模板.md"
TARGET_DIR="${PWD}/.agents"
TARGET_FILE="${TARGET_DIR}/PROJECT_CONTRACT.md"
IGNORE_FILE="${TARGET_DIR}/.gitignore"
CONFIG_FILE="${TARGET_DIR}/workflow.config"

if [ ! -f "$TEMPLATE" ]; then
    echo "❌ 未找到项目契约模板: $TEMPLATE" >&2
    exit 1
fi
mkdir -p "$TARGET_DIR/decisions" "$TARGET_DIR/fitness"
if [ ! -f "$IGNORE_FILE" ]; then
    cat >"$IGNORE_FILE" <<'EOF'
# 过程数据与本地快照默认不入库；长期项目知识显式放行。
*
!.gitignore
!PROJECT_CONTRACT.md
!decisions/
!decisions/**
!fitness/
!fitness/**
EOF
fi
if [ -f "$TARGET_FILE" ]; then
    echo "ℹ️  契约已存在，保持原文件不动: $TARGET_FILE"
else
    cp "$TEMPLATE" "$TARGET_FILE"
    echo "✅ 已创建 DRAFT 项目契约: $TARGET_FILE"
fi

if [ -f "$CONFIG_FILE" ]; then
    echo "ℹ️  本地证据配置已存在，保持原文件不动: $CONFIG_FILE"
else
    cat >"$CONFIG_FILE" <<'EOF'
# 本地运行配置；不提交版本库。按 .agents/PROJECT_CONTRACT.md 第 6 章填写真实命令。
CONTRACT_PATH=".agents/PROJECT_CONTRACT.md"
TEST_DIR="tests"
TEST_CMD=""
CORE_REGRESSION_CMD=""
SMOKE_CMD=""
LINT_CMD=""
BENCH_CMD=""
BENCH_THRESHOLD="3"
BENCH_HIGHER_IS_BETTER="0"
PERF_CRITICAL="0"
FAILURE_SIGNATURE_CMD=""
EOF
    echo "✅ 已创建本地证据配置骨架: $CONFIG_FILE"
fi

ROOT_IGNORE="${PWD}/.gitignore"
if [ -f "$ROOT_IGNORE" ] && grep -Eq '^[[:space:]]*/?\.agents/?[[:space:]]*$' "$ROOT_IGNORE"; then
    echo "⚠️  根目录 .gitignore 忽略了整个 .agents/；请放行 PROJECT_CONTRACT.md、decisions/ 与 fitness/。"
fi
echo "ℹ️  契约确认后运行: ${WORKFLOW_PACK}/scripts/capture_baseline.sh <用户认可的稳定标签或提交>"
