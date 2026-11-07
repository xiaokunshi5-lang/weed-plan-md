# 自动化与 GitHub 配置

这里收录仓库级自动化配置。它们属于发布仓库，不属于目标项目要拖走的工作流正文。

| 文件 | 用途 |
| :--- | :--- |
| [`../.github/workflows/test.yml`](../.github/workflows/test.yml) | 在 Ubuntu 上运行 Shell/JS 语法、Markdown 链接和 43 项隔离回归；不使用仓库密钥 |
| [`../.github/ISSUE_TEMPLATE/bug_report.yml`](../.github/ISSUE_TEMPLATE/bug_report.yml) | 让问题报告包含版本、影响范围、最小复现和环境信息 |

CI 使用标准 GitHub Actions、Bash、Git 和 Node.js。更改验证命令时，需要同步修改工作流文件、[`维护与测试/`](../维护与测试/README.md) 中的说明，以及贡献指南里的本地检查命令。
