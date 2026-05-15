# 测试场景 Test Scenarios

本文档列出 Git Release Pipeline 的手工验收测试场景，供发版前自测 / 贡献者验证。

自动化套件在 [`tests/run_all.sh`](./tests/run_all.sh)；本文档覆盖更宽的端到端场景。

## 场景 1 — 首次发版 First Release

**前置**：一个全新的 skill-structured 项目，根目录有 `skills/<name>/SKILL.md` + `tests/run_all.sh`。

```bash
cd your-new-project
PROJECT_ROOT=$(pwd) bash path/to/release.sh v0.1.0
```

**期望**：
- ✅ 创建 `Release/v0.1.0/` + `Release/CHANGELOG.md`
- ✅ `.skill` + tarball 生成
- ✅ CHANGELOG 自动写 TODO 占位，提示用户填写后重跑
- ✅ 第二次跑（填完 TODO 后）通过所有 gates

## 场景 2 — 版本号正则转义 Version Dot Escape (S2-2)

**前置**：CHANGELOG.md 中有 `## v1X0Y0` 条目（历史遗留）。

```bash
bash release.sh v1.0.0
```

**期望**：
- ✅ 不把 `v1.0.0` 的条目误匹配到 `v1X0Y0`
- ✅ audit §4 正确提取 v1.0.0 实际条目内容

## 场景 3 — 含空格文件名 Filename with Spaces (S2-1)

**前置**：项目中有 `docs/My Notes.md` 这类含空格路径。

```bash
bash release-sanitize.sh ./staged-dir
```

**期望**：
- ✅ `Notes.md` 被扫描（而不是因 xargs 分词静默跳过）
- ✅ 若含敏感信息，报告中路径显示完整

## 场景 4 — 双源漂移检测 Dual-Source Drift (S3-4)

**前置**：项目有 `scripts/release.sh` 和 `skills/<name>/scripts/release.sh`，两者 byte 不一致。

```bash
bash release.sh v1.0.0
```

**期望**：
- ✅ 发版 abort，提示具体漂移文件
- ✅ audit §9 FAIL（非 SKIP）

**变体**：只有一边有 `scripts/` → §9 也 FAIL（S3-4）。

## 场景 5 — SKILL.md version 一致性 (S3-3)

**前置**：`skills/<name>/SKILL.md` 的 `version: v0.9.5`，但传入 `release.sh v1.0.0`。

```bash
bash release.sh v1.0.0
```

**期望**：
- ✅ abort 并提示："SKILL.md version 不一致：SKILL.md=v0.9.5, 传入=v1.0.0"
- ✅ 不产生任何 Release/ 文件

## 场景 6 — RELEASE_NOTES KB 硬编码 (S3-6)

**前置**：手改 `Release/<ver>/RELEASE_NOTES.md`，加 `123 KB` 之类的字串。

```bash
bash release-audit.sh v1.0.0
```

**期望**：
- ✅ §10 FAIL（非软警告）
- ✅ 打印具体行号 + 内容

## 场景 7 — strict mode 未定义变量 (S3-7)

**前置**：人为往 `release.sh` 里加一行 `echo $UNDEFINED_VAR`。

```bash
bash release.sh v1.0.0
```

**期望**：
- ✅ 立即报错退出（`set -u` 触发），不继续执行

## 场景 8 — install.sh §6.10 契约

```bash
./install.sh --help              # 打印 usage，退出 0
./install.sh --dry-run           # 预览，不写文件，退出 0
./install.sh --force --dry-run   # 覆盖模式的预览
./install.sh --bogus-flag        # 退出 2，打印错误
./install.sh                     # 正式安装
./install.sh                     # 重复安装拒绝（除非加 --force）
```

**期望**：所有退出码和行为符合 INSTALL.md 文档。

## 场景 9 — 纯净目录 Sanity Clean

**前置**：把本仓库整包交给 `release-sanitize.sh` 扫。

```bash
bash scripts/release-sanitize.sh .
```

**期望**：
- ✅ 无敏感发现（除了 `tests/fixtures/` 明确豁免的 fixture 文件）
- ✅ 所有绝对路径 / 邮箱 / IP / MAC / 指纹都被文档域或私网段规则豁免

## 场景 10 — 自动化全套回归

```bash
bash tests/run_all.sh
```

**期望**：EXIT 0，所有 suites 全绿。
