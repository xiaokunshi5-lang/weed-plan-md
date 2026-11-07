# 开设项目时直接拖动

这个目录是给新项目用的完整工作流包。把目录里的所有文件和子目录拖入目标项目后，按下面顺序操作：

1. 在目标项目根目录打开 `项目适配与契约初始化工作流.md`，让 Agent 先调查项目并生成 `DRAFT` 契约。
2. 运行 `scripts/init_project_contract.sh`。它会创建 `.agents/PROJECT_CONTRACT.md`、本地配置骨架与长期知识目录，不覆盖已有文件。
3. 填写契约第 1 至 8 章，用户确认后把 `contract_status` 改为 `CONFIRMED`，并把契约、ADR 和可复用回归资产纳入项目 Git。
4. 在 `.agents/workflow.config` 填入真实测试、核心回归、冒烟、静态检查和性能命令。不要用 `true` 或 `exit 0` 冒充证据。
5. 在用户认可的稳定 Git 引用上运行 `scripts/capture_baseline.sh <stable-tag-or-commit>`。
6. 日常按任务打开 `计划工作流.md`、`程序修复工作流.md` 或 `UI审美与开源组件借鉴工作流.md`；UI 文档只在契约启用相应规则时使用。

## 目录内容

| 路径 | 作用 |
| :--- | :--- |
| `项目适配与契约初始化工作流.md` | 首次进入项目时确认第一要义、提问、激活契约 |
| `项目契约模板.md` | 由初始化脚本复制到 `.agents/PROJECT_CONTRACT.md` 的模板 |
| `计划工作流.md` | 新功能、重构、架构演进 |
| `程序修复工作流.md` | Bug、性能退步、效果纠偏 |
| `UI审美与开源组件借鉴工作流.md` | 按契约裁剪的 UI、动效与音效候选能力 |
| `工作流完善调研与实施计划.md` | 设计依据与参考项目；日常使用不必打开，保留它供自测和追溯 |
| `scripts/init_project_contract.sh` | 创建 `DRAFT` 契约和本地配置骨架 |
| `scripts/capture_baseline.sh` | 在稳定 Git 引用上捕获可信基线 |
| `scripts/watchdog_gate.sh` | 校验契约、基线、新增失败、核心路径、性能与静态检查 |
| `scripts/fix_attempt.sh` | 记录单根因修复尝试，检测重复假设与代码震荡 |
| `scripts/rollback.sh` | 创建救援分支并回滚，或处理非 Git 目录快照 |
| `scripts/ui_tactile_kit.js` | 仅在契约允许且用户确认音效时使用的可选 Web Audio 组件 |
| `tests/` | 验证这套工作流包本身；开设项目时可选保留，不参与项目业务测试 |

## 拖动边界

- 把本目录**整体**或本目录内所有内容一起放进目标项目；不要拆开只拖三个工作流 MD。
- 项目契约是进入目标项目后生成的，拖动包里只有模板。
- `.agents/workflow.config`、`.agents/baseline/`、修复日志与快照属于本地过程数据，由脚本生成或由用户填写，不随包预置。
- 脚本会执行 `.agents/workflow.config` 中的命令，部分脚本会创建 Git 提交、标签、救援分支或执行回滚。首次使用请在副本里试跑，并先用 `--dry-run` 预演回滚。
- 本目录中的运行文件与仓库根目录是同一份内容的硬链接副本，便于拖动，不代表两套独立版本。
