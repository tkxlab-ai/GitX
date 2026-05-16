# 安全策略 Security Policy

## 支持的版本 Supported Versions

只有最新的 minor 版本会收到安全修复。建议始终升级到最新 release。

| 版本 | 支持状态 |
|------|---------|
| 最新 minor (v0.9.x / v1.0.x 等) | ✅ 接受安全补丁 |
| 较老版本 | ❌ 请先升级 |

## 报告漏洞 Reporting a Vulnerability

**请不要在公开 issue 中报告安全漏洞。** 公开披露前请先私下联系维护者。

### 私下报告渠道

- **GitHub Security Advisory**（推荐）：
  在本仓库的 `Security` → `Report a vulnerability` 打开私密工单
- **邮箱**：`security@tkxlab.ai`（PGP 可选，按需索取公钥）

### 报告内容建议

一条有用的报告通常包含：
- 受影响的版本 / commit SHA
- 重现步骤（最小可复现用例）
- 实际影响（数据泄露 / 权限提升 / 代码执行 / DoS）
- 你已知的缓解方案（如有）

### 响应时间

| 阶段 | 目标 |
|------|------|
| 确认收到 | 3 个工作日内 |
| 初步评估 | 7 个工作日内 |
| 修复或缓解方案 | 视严重程度，通常 30 天内 |
| 公开披露 | 与报告者协商时间窗口 |

## 安全模型 Threat Model

本项目是一个本地运行的 Bash skill，**不涉及网络服务**。主要关注点：

1. **敏感信息泄露**：release 包不得包含 API key / 密码 / 私钥。由 `release-sanitize.sh` + `scan-credentials.sh` 在打包前扫描。
2. **命令注入**：版本号、路径参数均需严格校验；已启用 `set -euo pipefail`。
3. **依赖供应链**：本项目纯 Bash，零运行时依赖，减小攻击面。
4. **双源漂移**：`scripts/` 与 `skills/<name>/scripts/` 必须 byte-identical，防止审计盲点（policy v2.3）。

## 已知限制

- macOS 系统 Bash 3.2 默认，某些 strict 模式行为可能与 Bash 4+ 存在差异。建议 `brew install bash`。
- `release-sanitize.sh` 基于正则，存在误报/漏报可能；需人工复核扫描报告。

## 致谢

对负责任披露的安全研究者，我们会在修复的 release notes 中致谢（除非你希望匿名）。
