#!/usr/bin/env bash
# ==============================================================================
# 通用防灾无损回滚脚本: scripts/rollback.sh
# 适用范围: 计划工作流 (v3.1) & 程序修复工作流 (v2.1) 共用
# 核心保障:
#   1. 无论工作区是否干净，回滚前必将当前 HEAD 锁定至 rescue/head_<时间戳> 分支，
#      杜绝“已 Commit 的排障提交在 reset --hard 后从分支蒸发”的隐患。
#   2. 若存在未提交改动，自动封存至 rescue/wip_<时间戳> 分支，100% 可追溯。
#   3. 严格执行受保护资产白名单 (.env, .agents, 依赖目录, 正式版, 复现测试等)。
#   4. 零网络依赖识别主分支，支持 --dry-run 预演模式与 --list 快照列表。
#   5. 兼容非 Git 项目的目录级快照退化模式 (.agents/snapshots/)。
# ==============================================================================
set -euo pipefail

ACTION_OR_TARGET="${1:-}"
OPTION_FLAG="${2:-}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 读取 .agents/workflow.config 配置（若存在）
BASE_BRANCH_CFG=""
if [ -f ".agents/workflow.config" ]; then
    # shellcheck disable=SC1091
    source ".agents/workflow.config" || true
    BASE_BRANCH_CFG="${BASE_BRANCH:-}"
fi

usage() {
    cat <<EOF
用法:
  ./scripts/rollback.sh <target-tag-or-commit>            执行安全无损回滚
  ./scripts/rollback.sh <target-tag-or-commit> --dry-run  仅预演将发生的操作，不修改任何文件
  ./scripts/rollback.sh --list                            列出所有可用快照基线与救援分支
EOF
}

if [ -z "$ACTION_OR_TARGET" ] || [ "$ACTION_OR_TARGET" = "-h" ] || [ "$ACTION_OR_TARGET" = "--help" ]; then
    usage
    exit 1
fi

# ------------------------------------------------------------------------------
# 模式 A: 非 Git 仓库的目录快照退化回滚 (.agents/snapshots/)
# ------------------------------------------------------------------------------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    SNAP_ROOT=".agents/snapshots"
    if [ "$ACTION_OR_TARGET" = "--list" ] || [ "$ACTION_OR_TARGET" = "-l" ]; then
        echo "📂 [非 Git 模式] 当前可用目录快照 (${SNAP_ROOT}):"
        ls -1 "$SNAP_ROOT" 2>/dev/null || echo "  (暂无快照)"
        exit 0
    fi
    TARGET_SNAP="${SNAP_ROOT}/${ACTION_OR_TARGET}"
    if [ ! -d "$TARGET_SNAP" ]; then
        echo "❌ 错误: 未找到目录快照 ${TARGET_SNAP}"
        exit 1
    fi
    if [ "$OPTION_FLAG" = "--dry-run" ]; then
        echo "🔍 [Dry-Run 预演] 将备份当前目录至 ${SNAP_ROOT}/rescue_${TIMESTAMP}，并从 ${TARGET_SNAP} 恢复。"
        exit 0
    fi
    RESCUE_SNAP="${SNAP_ROOT}/rescue_${TIMESTAMP}"
    mkdir -p "$RESCUE_SNAP"
    rsync -a --exclude='.agents/snapshots' --exclude='node_modules' --exclude='.venv' ./ "$RESCUE_SNAP/"
    echo "📦 已将当前工作区封存至: ${RESCUE_SNAP}"
    rsync -a --delete --exclude='.agents' --exclude='node_modules' --exclude='.venv' --exclude='.env*' "${TARGET_SNAP}/" ./
    echo "🎉 [保险箱管理员] 已从目录快照 [${ACTION_OR_TARGET}] 无损恢复！"
    exit 0
fi

# ------------------------------------------------------------------------------
# 模式 B: 标准 Git 仓库防灾回滚
# ------------------------------------------------------------------------------
if [ "$ACTION_OR_TARGET" = "--list" ] || [ "$ACTION_OR_TARGET" = "-l" ]; then
    echo "🏷️  可用安全基线标签 (Tags):"
    git tag -l "pre-*" "checkpoint-*" "post-*" "v*-stable" | tail -20 || true
    echo ""
    echo "🛟 可用救援分支 (Rescue Branches):"
    git branch --list "rescue/*" || true
    echo ""
    echo "🔨 最近尝试提交 (Fix Attempts):"
    git tag -l "fix-attempt/*" | tail -10 || true
    exit 0
fi

TARGET_REF="$ACTION_OR_TARGET"
if ! git rev-parse --verify "${TARGET_REF}^{commit}" >/dev/null 2>&1; then
    echo "❌ 错误: 目标快照或提交 [${TARGET_REF}] 不存在！"
    echo "请运行 ./scripts/rollback.sh --list 查看可用基线。"
    exit 1
fi

CLEAN_ARGS=(
    -fd
    -e .env
    -e ".env.*"
    -e "*.key"
    -e "*.pem"
    -e "*.token"
    -e ".venv"
    -e "venv"
    -e "node_modules"
    -e ".agents"
    -e "release/"
    -e "dist/"
    -e "正式版/"
    -e "归档/"
    -e "scripts/"
    -e "tests/repro_*"
    -e "tests/test_repro_*"
)

HEAD_SHA=$(git rev-parse --short HEAD)
TARGET_SHA=$(git rev-parse --short "${TARGET_REF}^{commit}")

# Dry-Run 预演模式
if [ "$OPTION_FLAG" = "--dry-run" ]; then
    echo "🔍 [Dry-Run 预演模式] 不会修改任何文件："
    echo "  • 当前 HEAD (${HEAD_SHA}) 将被永久锁定至救援分支: rescue/head_${TIMESTAMP}"
    if [ -n "$(git status --porcelain)" ]; then
        echo "  • 检测到未提交改动，将被自动封存至救援分支: rescue/wip_${TIMESTAMP}"
    else
        echo "  • 当前工作区无未提交改动"
    fi
    echo "  • 主工作分支将重置 (reset --hard) 至: ${TARGET_REF} (${TARGET_SHA})"
    echo "  • 预计将被清理的未跟踪文件 (已应用白名单保护):"
    git clean -n "${CLEAN_ARGS[@]}" | sed 's/^/      /'
    exit 0
fi

echo "🛡️  [保险箱管理员] 启动安全防灾回滚流程..."

# 1. 确定主工作分支（零网络调用）
CURRENT_BRANCH=$(git symbolic-ref --short -q HEAD || echo "")
resolve_base_branch() {
    if [ -n "$BASE_BRANCH_CFG" ] && git show-ref --verify --quiet "refs/heads/${BASE_BRANCH_CFG}"; then
        echo "$BASE_BRANCH_CFG"
    elif git show-ref --verify --quiet refs/heads/main; then
        echo "main"
    elif git show-ref --verify --quiet refs/heads/master; then
        echo "master"
    else
        git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^rescue/' | head -n 1 || echo "main"
    fi
}

WORK_BRANCH="$CURRENT_BRANCH"
if [ -z "$WORK_BRANCH" ] || [[ "$WORK_BRANCH" == rescue/* ]]; then
    WORK_BRANCH=$(resolve_base_branch)
fi

# 2. 强制锁定当前 HEAD 至 rescue/head_<时间戳>，防止已提交的尝试在 reset 后丢失
RESCUE_HEAD_BRANCH="rescue/head_${TIMESTAMP}"
git branch "$RESCUE_HEAD_BRANCH" HEAD
echo "📌 已将当前提交 (${HEAD_SHA}) 锁定至救援分支: ${RESCUE_HEAD_BRANCH}"

# 3. 备份敏感环境配置文件至临时内存目录
TMP_ENV_BACKUP=$(mktemp -d 2>/dev/null || mktemp -d -t 'rollback_env')
trap 'rm -rf "$TMP_ENV_BACKUP"' EXIT
for env_file in .env .env.local .env.development .env.production; do
    if [ -f "$env_file" ]; then
        cp -p "$env_file" "${TMP_ENV_BACKUP}/${env_file}"
    fi
done

# 4. 若工作区存在未提交改动，自动创建 rescue/wip_<时间戳> 分支封存
if [ -n "$(git status --porcelain)" ]; then
    RESCUE_WIP_BRANCH="rescue/wip_${TIMESTAMP}"
    echo "📦 检测到未提交探索改动，正在封存至救援分支: ${RESCUE_WIP_BRANCH}..."
    git checkout -q -b "$RESCUE_WIP_BRANCH"
    git add -A
    git commit -q -m "chore(rescue): 自动封存回滚前的未提交代码碎片 [${TIMESTAMP}]" --no-verify || true
    echo "✅ 未提交代码已安全封存于 ${RESCUE_WIP_BRANCH}。"
fi

# 5. 切回主工作分支并重置到目标基线
if git show-ref --verify --quiet "refs/heads/${WORK_BRANCH}"; then
    git checkout -q "$WORK_BRANCH"
else
    git checkout -q -B "$WORK_BRANCH"
fi

echo "🔄 正在将分支 [${WORK_BRANCH}] 重置至基线: ${TARGET_REF} (${TARGET_SHA})..."
git reset --hard "${TARGET_REF}"

# 6. 按照白名单清理未跟踪杂质，并恢复敏感环境文件
echo "🧹 执行白名单受控清理..."
git clean "${CLEAN_ARGS[@]}" >/dev/null

for env_file in .env .env.local .env.development .env.production; do
    if [ -f "${TMP_ENV_BACKUP}/${env_file}" ]; then
        cp -p "${TMP_ENV_BACKUP}/${env_file}" "$env_file"
    fi
done

echo "🎉 [保险箱管理员] 已无损恢复至稳定基线 [${TARGET_REF}] (${TARGET_SHA})！"
echo "   如需找回回滚前状态，可随时检出: ${RESCUE_HEAD_BRANCH}${RESCUE_WIP_BRANCH:+ 或 $RESCUE_WIP_BRANCH}"
