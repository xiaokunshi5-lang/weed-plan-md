# WEED PLAN.MD

> 面向 AI Agent 的通用项目工作流：用项目契约、可信基线和证据门禁，保护项目第一要义与系统自洽。

**English:** A general-purpose workflow pack for AI coding agents. It records a project's first principle, design intent, and evidence-based non-regression gates before an agent changes code.

WEED PLAN.MD 是一个早期公开版本，由一组 Markdown 规范、一个项目契约模板和少量本地脚本组成。它不是框架、CLI 产品或自动重构工具，也不要求把项目源码上传到本仓库。

## 解决什么问题

一个稳定运行的版本，可能在静态审查里看起来“漏洞百出”：某段缓存、轮询、宽泛异常、兼容分支或绕过通用抽象的代码，单看并不漂亮，却服务于实时性、降级恢复、状态兼容或延迟预算。Agent 若把这些局部建议逐条“修正”，可能修好一个点，却破坏整条核心链路。

本工作流要求 Agent 在改代码前先回答三个问题：

1. 这个项目最不能失去什么？
2. 这段关键代码为什么这样写？
3. 用什么证据证明改动没有让系统变坏？

审查工具的每条意见只是待验证假设，结论必须是 `采纳`、`拒绝` 或 `暂缓`，并附代码证据和对项目首要目标的影响。缺少验证时只能报告 `PARTIAL`，不能冒充 `PASS`。

## 通用流程，项目专属目标

全局模板不预设“稳定性、速度、美观”谁永远第一。进入项目后，Agent 先只读调查仓库证据，再与用户确认 `.agents/PROJECT_CONTRACT.md`，生成项目专属质量排序。

| 场景 | 可能被确认的首要维度 | 典型取舍 |
| :--- | :--- | :--- |
| 同声传译 | 连续可用、准确性、首字与端到端时延 | 为提升准确率增加等待，是否越过实时性底线？ |
| 游戏 | 可玩性、安全性、输入响应 | 防作弊校验是否可以牺牲操作手感？ |
| 体验型前端 | 审美、交流感、无障碍、首屏代价 | 动效与素材体积是否损害可用性？ |

这些只是启发示例，不是按目录名套用的固定答案。契约保护已确认的不变量与设计原因，不保护已证实的缺陷。

## 五分钟上手

环境要求：Bash、Git、Node.js（仅用于检查可选的 UI 脚本）。工作流脚本主要在类 Unix 环境验证；正式可信基线要求目标项目是 Git 仓库。

```bash
git clone https://github.com/xiaokunshi5-lang/weed-plan-md.git
cd weed-plan-md
bash tests/test_project_aware_workflow.sh
```

进入你的目标项目，并把本仓库作为工作流包使用：

```bash
cd /path/to/your-project
WORKFLOW_PACK="/path/to/weed-plan-md"
"${WORKFLOW_PACK}/scripts/init_project_contract.sh"
```

然后：

1. 唤醒 [`项目适配与契约初始化工作流.md`](./项目适配与契约初始化工作流.md)。Agent 先读 README、入口、测试、配置和既有 Agent 指令，再一次只问一个会改变质量排序或验收的问题。
2. 填写 `.agents/PROJECT_CONTRACT.md` 第 1 至 8 章，删除全部 `{{...}}` 占位符；用户确认后把 `contract_status` 改为 `CONFIRMED`，并将契约、ADR 和可复用回归资产纳入项目 Git。
3. 把真实测试、核心回归、冒烟、静态检查和性能命令填入本地 `.agents/workflow.config`。不要用 `true` 或 `exit 0` 冒充证据。
4. 在用户认可的稳定提交或标签上捕获基线：

```bash
"${WORKFLOW_PACK}/scripts/capture_baseline.sh <stable-tag-or-commit>"
```

5. 日常按任务唤醒全局工作流：

| 任务 | 入口 |
| :--- | :--- |
| 新功能、重构、架构演进 | [`计划工作流.md`](./计划工作流.md) |
| Bug、性能退步、效果纠偏 | [`程序修复工作流.md`](./程序修复工作流.md) |
| 前端、视觉、微交互 | 先读契约，再按需使用 [`UI审美与开源组件借鉴工作流.md`](./UI审美与开源组件借鉴工作流.md) |

长期契约和 ADR 属于项目仓库；`workflow.config`、数值基线、修复日志、交接单和快照默认保持本地。工作流包也可以整体复制到目标项目，此时上述 `WORKFLOW_PACK` 可替换为项目内相对路径。

## 文档地图

- [`项目适配与契约初始化工作流.md`](./项目适配与契约初始化工作流.md)：首次进入项目时的调查、提问、确认与激活流程。
- [`项目契约模板.md`](./项目契约模板.md)：`.agents/PROJECT_CONTRACT.md` 的字段说明。
- [`计划工作流.md`](./计划工作流.md)：规范驱动计划、任务分级、验收与多角色协作。
- [`程序修复工作流.md`](./程序修复工作流.md)：根因定位、微创修复、回滚和防复发。
- [`UI审美与开源组件借鉴工作流.md`](./UI审美与开源组件借鉴工作流.md)：按项目契约裁剪的候选 UI 能力库。
- [`工作流完善调研与实施计划.md`](./工作流完善调研与实施计划.md)：设计依据、参考项目与既有工作流改造记录。
- [`OPEN_SOURCE_PLAN.md`](./OPEN_SOURCE_PLAN.md)：公开版本定位、发布边界与版本化策略。

## 脚本与证据门禁

| 脚本 | 作用 |
| :--- | :--- |
| [`scripts/init_project_contract.sh`](./scripts/init_project_contract.sh) | 创建 `DRAFT` 契约和本地配置骨架，不覆盖已有文件 |
| [`scripts/capture_baseline.sh`](./scripts/capture_baseline.sh) | 在稳定 Git 引用上记录测试失败签名、核心回归、冒烟、静态检查与性能数值 |
| [`scripts/watchdog_gate.sh`](./scripts/watchdog_gate.sh) | 校验契约、基线、防篡改、新增失败、核心路径、性能与静态检查 |
| [`scripts/fix_attempt.sh`](./scripts/fix_attempt.sh) | 记录单根因修复尝试，检测重复假设与代码震荡 |
| [`scripts/rollback.sh`](./scripts/rollback.sh) | 创建救援分支并回滚，或处理非 Git 目录快照 |
| [`scripts/ui_tactile_kit.js`](./scripts/ui_tactile_kit.js) | 仅在契约允许且用户确认音效时使用的可选 Web Audio 组件 |

脚本会读取本地 `.agents/workflow.config`，通过 `bash -c` 执行你填写的证据命令，其中部分脚本会创建 Git 提交、标签、救援分支或执行回滚。请先在临时副本中理解脚本行为；推荐先用 `--dry-run` 预演回滚，并始终保留独立备份。

## 验证

```bash
bash -n scripts/*.sh
node --input-type=module --check < scripts/ui_tactile_kit.js
bash tests/check_markdown_links.sh
bash tests/test_project_aware_workflow.sh
```

回归测试只在临时目录创建隔离的 Git / 非 Git 项目，不会修改当前工作区中的业务文件。

## 能力边界

- 这是降低“局部正确、全局破坏”概率的流程与证据约束，不保证零回归，也不能替代代表性测试、监控和人工验收。
- 契约质量取决于真实证据和用户确认；自动探测到的内容必须标注为推断，不能伪装成结论。
- 非 Git 目录仅支持目录快照回滚，不能作为正式可信基线。
- 主要脚本和回归测试在类 Unix 环境验证；Windows 原生环境尚未纳入测试矩阵。
- 参考的开源项目用于说明设计灵感，不代表它们参与维护或背书本仓库。复制 UI 片段前须逐项核验其当前许可。

## 贡献、安全与许可

欢迎从可复现的问题、文档歧义和测试缺口开始贡献，参见 [`CONTRIBUTING.md`](./CONTRIBUTING.md)。安全或隐私问题请按 [`SECURITY.md`](./SECURITY.md) 私下报告，不要直接公开 Issue。

本仓库采用 [MIT License](./LICENSE)；外部资料、组件和示例的许可需按各自来源单独核验。
