# 维护与测试

这里收录的是「检查工作流本身是否还可靠」的入口，不是开项目时必须拖走的业务流程。

- [`../tests/test_project_aware_workflow.sh`](../tests/test_project_aware_workflow.sh)：43 项隔离回归，覆盖契约草稿阻断、基线原子写入、证据篡改、性能退步、显式豁免和非 Git 回滚。
- [`../tests/check_markdown_links.sh`](../tests/check_markdown_links.sh)：检查仓库内 Markdown 本地链接和代码块配对。
- [`../scripts/ui_tactile_kit.js`](../scripts/ui_tactile_kit.js)：可选 UI 音效组件，语法检查按 ES Module 处理。

在工作流仓库根目录运行：

```bash
bash -n scripts/*.sh tests/*.sh
node --input-type=module --check < scripts/ui_tactile_kit.js
bash tests/check_markdown_links.sh
bash tests/test_project_aware_workflow.sh
```

回归测试只在临时目录创建隔离的 Git / 非 Git 项目，不会修改当前工作区中的业务文件。改动脚本、契约模板或门禁语义时，应至少新增一条对应断言。
