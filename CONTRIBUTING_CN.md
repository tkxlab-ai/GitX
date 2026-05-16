# 贡献指南（中文）

[English](CONTRIBUTING.md) · [中文](CONTRIBUTING_CN.md)

欢迎为 GitX 贡献代码、文档、测试或反馈。

## 开发环境

```bash
git clone https://github.com/tkxlab-ai/GitX.git
cd GitX

bash --version              # 需要 3.2+（POSIX）
which shellcheck            # 建议装：brew install shellcheck

bash tests/run_all.sh       # 跑全套测试
```

## 开发流程（严格 TDD）

1. **RED** — 先写失败的测试（`tests/test_*.sh`），确认它 FAIL
2. **GREEN** — 最小改动让测试通过
3. **REFACTOR** — 清理代码，保持全套回归绿
4. **提交** — 描述改了哪条政策 / 修了哪个 Gotcha（写 Why，不写 What）

## 测试要求

- 新功能必须配套测试用例
- 修 bug 必须先写回归测试复现，再修复
- PR 合并前：`bash tests/run_all.sh` 必须全绿
- 跨平台：测试应在 macOS + Linux 都能跑（避免 GNU-only 选项）

## 提交规范

```
<type>: <description>

<optional body：解释 Why>

Refs: <issue 或 政策 §>
```

Types：`feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `perf` / `ci`

### PR 清单

- [ ] `bash tests/run_all.sh` → 全绿
- [ ] 新增/修改政策条款对应 `references/TKX_*.md` 引用
- [ ] 改了 `scripts/*.sh` → 跑 `bash scripts/sync-dual-source.sh` 同步双源（v2.3 §8.1 #14）
- [ ] 改了 SKILL.md → `version:` / 双源对齐
- [ ] 改动有对应 Gotcha / Dev Log 条目（适用时）

## 代码风格

- Shell：`set -euo pipefail`，命名清晰，无 silent fallback
- 错误：显式抛出 + 可执行修复提示（禁止占位符式错误信息）
- 注释：解释 Why，不解释 What
- 文件 ≤ 800 行，函数 ≤ 50 行

## 行为准则

遵循 [Contributor Covenant](CODE_OF_CONDUCT.md)。

## 许可

贡献代码视为同意以 [MIT License](LICENSE) 发布。
