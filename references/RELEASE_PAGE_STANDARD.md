# Release Page Standard — 发版页面标准

> 适用于所有用 GitX（`/gitx-release`）发版的项目。目标：每个项目在 GitHub 上的首页（README.md / README_CN.md）结构一致、内容可核对、中英文对等；每次发版带齐同一套产物与元数据。
> 参考样板：GitX 自己的 README。每条规则后面的【关卡】注明由哪道检查强制执行；标【评审】的只能靠人或审查智能体把关。

---

## 1. 页面顶部（按顺序）

顶部放在一个居中块 `<div align="center">` 里，块内依次为：

| # | 元素 | 规则 | 关卡 |
|---|---|---|---|
| 1 | 标题 | `# <项目名> — <一句话说明它是什么>`，例：`# GitX — Fail-Closed Release Pipeline for AI Agent Skills` | 评审 |
| 2 | 口号 | 一行加粗，说清给谁解决什么问题；可再跟最多两句说明 | 评审 |
| 3 | 徽章行 | 必需：License、Release（动态 `img.shields.io/github/v/release/…`，不手写版本号）、Tests（自动区块里的 `tests-N suites / 0 fail`）、平台或 CLI。首次发版后加 Deep Audit（`deep audit-N/0/M`，N 必须等于审计实际总数）。可选：Status 等。同一仓库只用一种徽章样式 | Tests 数字：H4；Deep Audit 数字：§0f/§0i |
| 4 | 语言切换 | `[English](README.md) · [中文](README_CN.md)`，**紧贴徽章行下方**，中英文两份都要有 | H10（链接可解析） |
| 5 | 首图（可选） | 用仓库内相对路径；若在 manifest 声明 `hero_asset:`，该文件必须存在 | H10 |

居中块之后依次为：

| # | 元素 | 规则 | 关卡 |
|---|---|---|---|
| 6 | 提示框 | 一行 `> 🔄 …`：说明能在哪些智能体 / CLI 中使用，或最重要的一条使用前提 | 评审 |
| 7 | 构建指标 | 自动区块 `build-metrics`；版本与日期写在标签后：`Version **…**` · `Released **…**`（中文：`版本 **…**` · `发版日期 **…**`），由脚本填写 | H4、H6 |
| 8 | 快捷链接栏 | `**[Documentation](#table-of-contents) · [Changelog](CHANGELOG.md) · [Report a bug](…/issues) · [Security](SECURITY.md)**` | H10 |

## 2. 正文章节（编号与顺序）

`What's New` 与 `Table of Contents` 不编号，其余章节标题带编号 `## N. 标题`。顺序由 `references/docs-contract/manifest.txt` 规定，必需章节缺失或顺序错误都会失败。可以在必需章节之间加自己的章节（不在清单里的标题不受检查）。

| 编号 | 英文标题 | 中文标题 | 内容要求 | 关卡 |
|---|---|---|---|---|
| — | What's New | 更新摘要 | 自动区块 `whats-new`，来自 CHANGELOG 最新一条 | H6 |
| — | Table of Contents | 目录 | 编号列表，顺序与正文一致，锚点必须能跳转 | test_toc_order、H12 |
| 1 | Why <项目名> | 为什么选择 <项目名> | 一张"问题 → 后果 → 本项目怎么解决"表；一段核心方法；一段与同类工具的定位；自动区块 `metrics`（By the numbers） | H1、H6 |
| 2 | Philosophy | 设计理念 | 每条原则一个小节：一行引言（注明出处）+ 本项目在代码里怎么落实 | H1、评审 |
| 3 | How It Works（流水线类项目可用 Pipeline & Audit Gates） | 工作原理（或 流水线与审计闸） | 一张流程图或结构图；一张模型表（产物 / 信息分类 → 由谁生成 → 由谁验证） | H1 |
| 4 | Quick Start | 快速开始 | `### 1 · Prerequisites`、`### 2 · Install`、`### 3 · <第一次使用>`、`### Upgrade`、`### Uninstall`；运行样例与排错放进 `<details>` | H1、§2b（安装标题） |
| 5 | Command Surface | 命令面 | 自动区块 `command-surface`；脚本直调表放进 `<details>` | H1、H6 |
| 6 | Configuration | 配置 | 环境变量表 + 关键文件表 | H1 |
| 7 | Testing | 测试 | 自动区块 `suite-count` + 覆盖范围表 + CI 实际运行内容（如实写） | H1、H6 |
| 8 | Security | 安全 | 威胁模型、凭证处理、漏洞私下报告方式 | H1 |
| 9 | Compatibility | 兼容性 | 操作系统 / shell / CLI，写明哪些在 CI 中实测 | H1 |
| 10 | FAQ | 常见问题 | 3–6 条，用 `<details>` | H1 |
| 11 | Research & References | 研究与参考 | 参考作品表（作品 · 作者 · 用在哪里）+ 延伸阅读 + 一行鸣谢 | H1 |
| 12 | Contributing | 贡献 | 步骤清单，与 `CONTRIBUTING.md` 一致 | H1 |
| 13 | License | 许可 | 许可证名 + 链接 `LICENSE`，必须是最后一节 | H1、test_readme_template_parity |

页面结尾放一个居中的页脚：仓库链接 + 一句话定位。

## 3. 写法规则

- **每个说法都要能在代码里核对。** 写"会做什么"之前先确认代码真的这样做；可选步骤、演练模式、CI 实际跑什么，都要如实写，不夸大。【评审】
- **数字只来自机器。** 会变化的数字（测试套件数、审计项数、发版次数、日期）只能出现在自动区块、带标签的子标记或徽章里；正文不写手工数字。【H4/H6 管自动区块与子标记，§0f/§0i 管 Deep Audit 数；其余为评审】
- **理念有出处。** 引言必须注明作者与作品（或标准名称），并写清落在哪段代码。【评审】
- **页内锚点按 GitHub 规则生成。** 小写，去掉除字母、数字、空格、`-`、`_`、汉字以外的字符，空格变 `-`，不合并连字符（`Pipeline & Audit Gates` → `pipeline--audit-gates`，`1. Why GitX` → `1-why-gitx`）。被链接的标题不要用 emoji、`·`、`—` 或中文标点。【H12】

## 4. 中英文规则

- 两份 README 章节相同、顺序相同、意思相同；数字与链接一致。【H2；意思对等：评审】
- 中文文件里不得出现连续 8 个以上的英文单词（代码、链接与白名单词除外）。【H3】
- 中文版里，有中文版本的文档要链接到中文版（`CHANGELOG_CN.md`、`CONTRIBUTING_CN.md`）；只有英文的文档在链接旁标"（英文）"。【评审】

## 5. 禁止内容

- 维护者的私有记录：Gotcha / Dev Log / Decision 编号、`HANDOFF*.md`、`GOTCHAS.md`、`Handoff*_Logs` 等。产品本身确实要提到这类文件名时（例如交接工具），在 manifest 里加 `h11_allow: <正则>` 豁免对应行。【H11】
- 私有主机名、组织名、账号、端口、绝对用户路径、凭证。【release-sanitize、GitHub SOP 泄露检查】
- 内部黑话与自我评价（如 "production-ready" 之外的空泛形容、内部代号）。【评审】
- 公开仓 `docs/` 里放内部规划文档。【评审】

## 6. 自动区块

| 区块 | 内容 | 生成 |
|---|---|---|
| `badges` | 徽章行（人工维护，脚本只更新测试数） | docs-pipeline 子标记 |
| `build-metrics` | 版本 · 发版日期 · 所用模型 · token 估算 | docs-pipeline 子标记 |
| `whats-new` | CHANGELOG 最新一条 | docs-pipeline |
| `metrics` | 发版次数 · 首次到最新发版日期 · 测试套件数 | docs-pipeline |
| `command-surface` | 命令表 | docs-pipeline |
| `suite-count` | 测试套件数 | docs-pipeline |

## 7. 发版清单

每次发版都要满足：

1. `Release/CHANGELOG.md` 与 `_CN.md` 顶部是本版本的真实条目，**日期 = 实际发版日**（长期未发的版本发布前要改到当天）。【changelog gate、H5】
2. `/gitx-release` 全部通过：测试、双源、密钥扫描、docs-audit、Deep Audit。【流水线】
3. GitHub：按 `.gitx/GITHUB_RELEASE_SOP.md` 发布；每个 tag 都有 Release，附件为 `.skill`、`checksums.txt`、`sbom.cyclonedx.json`；先草稿、再由负责人确认公开。【SOP 8.4】
4. 仓库元数据：About 描述准确、无错别字；设置 topics。【评审】
5. 社区文件齐全：`LICENSE`、`SECURITY.md`、`CODE_OF_CONDUCT.md`、`CONTRIBUTING.md` + `CONTRIBUTING_CN.md`、`INSTALL.md`、`.github/ISSUE_TEMPLATE/`（缺陷、功能、选择页）、`.github/PULL_REQUEST_TEMPLATE.md`。【H10 管 README 链接到的文件；其余评审】
6. 可选：中央 marketplace 版本更新（`.gitx/marketplace-target`）；私有 Gitea 发布仓（`.gitx/gitea-release-target`）；"推送并发布"话术见 SKILL.md。【发版后步骤】

## 8. 已有 README 如何迁移

1. 从技能目录复制 `references/docs-contract/manifest.txt` 与 `cjk-allow.txt` 到项目的同名位置（删掉 `hero_asset:` 行，除非项目有首图）。
2. 参照 `references/readme/README.template.md` / `README_CN.template.md` 改写两份 README（`docs-pipeline --init --force` 会整份覆盖，先备份）。
3. 运行 `scripts/docs-pipeline.sh` 填充自动区块，再运行 `scripts/docs-audit.sh`，按报错逐条修正，直到退出码为 0。
