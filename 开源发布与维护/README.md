# 开源发布与维护

这里收录的是「维护这个 GitHub 仓库」所需的文件，不需要拖进使用工作流的目标项目。

| 文件 | 用途 |
| :--- | :--- |
| [`../README.md`](../README.md) | 项目定位、工作方式、第一次接入、文件地图和能力边界 |
| [`../LICENSE`](../LICENSE) | MIT 许可证 |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | 贡献流程、验证要求与 PR 清单 |
| [`../SECURITY.md`](../SECURITY.md) | 安全报告范围、脚本执行边界与用户注意事项 |
| [`../CHANGELOG.md`](../CHANGELOG.md) | 版本记录 |
| [`../OPEN_SOURCE_PLAN.md`](../OPEN_SOURCE_PLAN.md) | 公开版本定位、发布边界与版本化策略 |
| [`../AGENTS.md`](../AGENTS.md) | 维护本仓库时的 Agent 规则 |
| [`../.gitignore`](../.gitignore) | 排除本地状态、凭据、快照和生成物 |

准备发布时，先跑 [`维护与测试/`](../维护与测试/README.md) 里的全部检查，再更新 `CHANGELOG.md`。公开仓库上的更正使用新提交，不改写已有公开历史；Release 只在实际功能和测试都确认后创建。
