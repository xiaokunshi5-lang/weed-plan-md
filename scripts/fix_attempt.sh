#!/usr/bin/env bash
# ==============================================================================
# 主刀医生微创尝试记录与震荡熔断检测器: scripts/fix_attempt.sh
# 适用范围: 程序修复工作流 (v2.1) & 计划工作流 (v3.1)
# 核心功能:
#   1. 自动为每次修复尝试编号并打标签: fix-attempt/<issue-id>/<n>
#   2. 自动维护 .agents/fix-log/ISSUE-<issue-id>.md 假设日志
#   3. 精确检测“A -> B -> A 代码震荡”或“空改动重复提交” (Exit 201)
#   4. 精确检测“同一病灶连续试错超过 2 次上限” (Exit 202)
# ==============================================================================
set -euo pipefail

ISSUE_ID="${1:-}"
HYPOTHESIS="${2:-}"
CONTRACT_PATH=".agents/PROJECT_CONTRACT.md"

if [ -z "$ISSUE_ID" ] || [ -z "$HYPOTHESIS" ]; then
    echo "用法: ./scripts/fix_attempt.sh <issue-id> \"<本次修复的根因假设摘要>\""
    echo "示例: ./scripts/fix_attempt.sh 104 \"LRU 缓存满时未淘汰队尾节点\""
    exit 1
fi

# 项目契约与可信基线是所有微创修复尝试的前置条件。
if [ ! -f "$CONTRACT_PATH" ]; then
    echo "⚡ [Exit 200] 缺少 ${CONTRACT_PATH}；先执行项目适配与契约初始化工作流。"
    exit 200
fi
CONTRACT_STATUS=$(sed -n 's/^contract_status:[[:space:]]*//p' "$CONTRACT_PATH" | head -n 1 | tr -d '"')
if [ "$CONTRACT_STATUS" != "CONFIRMED" ] || grep -q '{{' "$CONTRACT_PATH"; then
    echo "⚡ [Exit 200] 项目契约未确认或仍含占位符，禁止记录修复尝试。"
    exit 200
fi
if [ ! -f ".agents/baseline/manifest.env" ]; then
    echo "⚡ [Exit 200] 缺少可信基线；先运行 ./scripts/capture_baseline.sh <stable-ref>。"
    exit 200
fi
# shellcheck disable=SC1091
source .agents/baseline/manifest.env || {
    echo "⚡ [Exit 200] 可信基线清单不可读；重新运行 capture_baseline.sh。"
    exit 200
}
sha256_file() {
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' \
        || sha256sum "$1" 2>/dev/null | awk '{print $1}'
}
if [ "${BASELINE_CONTRACT_SHA256:-}" != "$(sha256_file "$CONTRACT_PATH")" ]; then
    echo "⚡ [Exit 200] 契约相对可信基线已改变；确认修订并重新捕获基线。"
    exit 200
fi

mkdir -p .agents/fix-log
LOG_FILE=".agents/fix-log/ISSUE-${ISSUE_ID}.md"

if [ ! -f "$LOG_FILE" ]; then
    cat <<EOF > "$LOG_FILE"
# 修复病历与假设日志: ISSUE-${ISSUE_ID}

| 尝试序号 | 时间 | 根因假设摘要 | 标签 (Git Tag) | 看门狗结论 |
| :--- | :--- | :--- | :--- | :--- |
EOF
fi

# 1. 计算当前尝试序号 N
EXISTING_COUNT=$(git tag -l "fix-attempt/${ISSUE_ID}/*" | wc -l | tr -d ' ')
NEXT_N=$((EXISTING_COUNT + 1))
CURRENT_TAG="fix-attempt/${ISSUE_ID}/${NEXT_N}"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# 2. 检查是否触发连续试错次数上限 (同一病灶最多允许 2 次试错，第 3 次尝试前强制跳闸)
if [ "$NEXT_N" -gt 2 ] && [ "${ALLOW_SECOND_OPINION:-0}" != "1" ]; then
    echo "⚡ ==========================================================="
    echo "   [破局断路器 TRIP (Exit 202)] 同一病灶连续试错已达 2 次上限！"
    echo "   当前请求为第 ${NEXT_N} 次尝试，严禁继续盲目堆叠补丁。"
    echo "   请立即执行:"
    echo "     1. ./scripts/rollback.sh <pre-fix-tag>"
    echo "     2. 填写 .agents/HANDOFF.md 并启动【第二意见通道】或向用户升级共商。"
    echo "==========================================================="
    exit 202
fi

# 3. 检查是否重复了已在假设日志中出现过的完全相同假设
if grep -Fq "| ${HYPOTHESIS} |" "$LOG_FILE"; then
    echo "⚡ [破局断路器 TRIP (Exit 203)] 检测到重复假设：\"${HYPOTHESIS}\" 已在历史尝试中验证过！"
    exit 203
fi

# 4. 提交当前代码改动并打标签
if [ -n "$(git status --porcelain -- . ':(exclude).agents')" ]; then
    git add -A -- . ':(exclude).agents'
    git commit -q -m "fix(${ISSUE_ID}): attempt #${NEXT_N} - ${HYPOTHESIS}" --no-verify
fi

git tag -f "$CURRENT_TAG" HEAD

# 5. 震荡检测: 与历史尝试对比代码树是否完全一致 (A -> B -> A)
if [ "$NEXT_N" -ge 2 ]; then
    for ((PREV_IDX = 1; PREV_IDX < NEXT_N; PREV_IDX++)); do
        PREV_TAG="fix-attempt/${ISSUE_ID}/${PREV_IDX}"
        if git rev-parse --verify "${PREV_TAG}^{commit}" >/dev/null 2>&1; then
            if git diff --quiet "$PREV_TAG" "$CURRENT_TAG" -- . ':(exclude).agents'; then
                echo "| #${NEXT_N} | ${TIMESTAMP} | ${HYPOTHESIS} | \`${CURRENT_TAG}\` | ⚡ 触发代码震荡跳闸 (与 #${PREV_IDX} 相同) |" >> "$LOG_FILE"
                echo "⚡ ==========================================================="
                echo "   [破局断路器 TRIP (Exit 201)] 检测到代码震荡！"
                echo "   本次尝试 (#${NEXT_N}) 的代码状态与历史尝试 (#${PREV_IDX}) 完全相同 (A -> B -> A)。"
                echo "   请立即执行 ./scripts/rollback.sh 回滚并切换架构思路！"
                echo "==========================================================="
                exit 201
            fi
        fi
    done
fi

# 6. 写入假设日志
echo "| #${NEXT_N} | ${TIMESTAMP} | ${HYPOTHESIS} | \`${CURRENT_TAG}\` | ⏳ 待看门狗终审 |" >> "$LOG_FILE"
echo "🩺 [主刀医生] 已记录第 #${NEXT_N} 次微创尝试: ${CURRENT_TAG}"
echo "   假设日志已更新: ${LOG_FILE}"
echo "   下一步请由看门狗执行: ./scripts/watchdog_gate.sh <复现脚本>"
