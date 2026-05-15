# 贡献指南 Contributing

欢迎为 Git Release Pipeline 贡献代码、文档、测试或反馈。

## 开发环境 Development Setup

```bash
git clone https://github.com/TKXLAB-AI/gitx-release.git
cd gitx-release

# 安装依赖（纯 bash，无外部依赖）
bash --version              # 需要 4.x+
which shellcheck            # 建议装：brew install shellcheck

# 跑测试
bash tests/run_all.sh
```

## 开发流程 Development Workflow

项目严格遵循 TDD：

1. **RED** — 先写失败的测试（`tests/test_*.sh`），确认它 FAIL
2. **GREEN** — 最小改动让测试通过
3. **REFACTOR** — 清理代码，保持全套回归绿
4. **提交** — 描述改了哪条政策 / 修了哪个 Gotcha

## 测试要求 Testing

- 新功能必须配套测试用例
- 修 bug 必须先写回归测试复现问题，再修复
- PR 合并前：`bash tests/run_all.sh` 必须全绿
- 跨平台：测试应在 macOS + Linux 都能跑（避免 GNU-only 选项）

## 提交规范 Commit / Pull Request

### Commit message 格式

```
<type>: <description>

<optional body with "why">

Refs: <issue or policy §>
```

Types: `feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `perf` / `ci`

### PR 清单

- [ ] 已跑 `bash tests/run_all.sh` → 全绿
- [ ] 新增 / 修改的政策条款对应 `references/TKX_*.md` 引用
- [ ] 若改了 `scripts/*.sh`，运行 `bash scripts/sync-dual-source.sh` 同步双源（dual-source policy v2.3 §8.1 #14）
- [ ] 若改了 SKILL.md，`version:` 字段已对齐
- [ ] 改动有对应 Gotcha / Dev Log 条目（适用时）

## 代码风格 Code Style

- Shell：`set -euo pipefail`，命名清晰，无 silent fallback
- 错误：显式抛出 + 可执行修复提示（禁止 `<请修复>` 类占位符）
- 注释：解释 WHY，不解释 WHAT
- 文件长度 ≤ 800 行，函数 ≤ 50 行

## 行为准则 Code of Conduct

本项目遵循 [Contributor Covenant](./CODE_OF_CONDUCT.md)。

## 许可 License

贡献代码视为同意以 [MIT License](./LICENSE) 发布。
