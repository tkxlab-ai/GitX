# 路线图 Roadmap

本文档记录 Git Release Pipeline 的阶段性发布计划与通用化方向。每个 milestone 都是**已做**或**已承诺做**，不是 wish list。

---

## 当前状态 — 多 CLI Skill Edition（版本号见 `VERSION` / `Release/CHANGELOG.md`）

**定位**：Claude skill 项目的发版管线。

**适用项目形态**：
- 根目录下 `skills/<name>/SKILL.md` + `tests/run_all.sh`
- 双源结构：`scripts/` 与 `skills/<name>/scripts/` byte-identical

**已实现能力**：
- 3 阶段 sanity 扫描（staging / `.skill` 内部 / 平摊后产物）
- 6 维敏感信息检测 + 30+ 凭证模式
- `.sanitize-ignore` 显式白名单（S3-1）
- CHANGELOG 真实性 gate + 版本号点号转义（S2-2）
- 双源漂移检测（S3-4）
- `.skill` + source tarball + `checksums.txt` 三产物
- 开源合规 audit（§11a-§11h，含开源四件套 / LICENSE / install.sh §6.10 / sha256 digest）
- `set -euo pipefail` 严格模式（S3-7）

**不支持**：Rust / Go / Python / Swift / 纯源码项目等其他生态。

---

## v1.0 — Universal Pipeline（Swift 首发）

**目标**：把 skill-specific 的假设从主管线抽离，引入 `PROJECT_TYPE` 插件模型；Swift 作为首个非-skill 参考实现。

**动机**：
- 当前 `release-sanitize.sh` / `scan-credentials.sh` / CHANGELOG gate / audit §3/§4/§7/§10/§11 已经**语言无关**（约 85% 通用）
- 绑死 skill 的只剩版本源、产物格式、双源 §9、`.skill` 打包 — 这些是**可抽象**的
- Swift 是首选验证对象：Apple 生态对签名/公证有明确规范，跑通 Swift 路径能同时打磨签名基础设施

### 架构：PROJECT_TYPE 插件模型

```
scripts/
├── release.sh                    # 主编排：通用 pre-flight + sanity + audit
├── release-audit.sh              # 通用 audit + 条件化章节
├── release-sanitize.sh           # 完全通用（已是）
├── scan-credentials.sh           # 完全通用（已是）
└── types/
    ├── skill.sh                  # v0.9.x 现有逻辑抽出
    └── spm.sh                    # v1.0 新增：Swift Package Manager
```

### 插件接口契约

每个 `types/<type>.sh` 必须导出：

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `detect()` | — | exit 0 = 命中；1 = 不命中 | 基于项目元数据文件推断类型 |
| `read_version()` | — | stdout: `vX.Y.Z` | 从类型专属文件读版本号 |
| `validate_version_consistency <arg>` | CLI 传入版本 | exit 0/1 | 校验源码元数据与 CLI 参数一致 |
| `build_artifacts <out_dir>` | 输出目录 | 产物写到 `$out_dir/` | 产出分发包 |
| `audit_extras <release_dir>` | release 目录 | stdout PASS/FAIL 摘要 | 类型专属 audit 章节 |
| `excluded_from_rsync()` | — | stdout: 一行一个 path pattern | 类型特有的 staging 排除项 |

### Swift 插件（`types/spm.sh`）规格

**detect**：存在 `Package.swift` 且顶层 manifest 含 `// swift-tools-version:`。

**read_version**：
- 优先：`Package.swift` 中 `let version = "X.Y.Z"` 常量
- fallback：`git describe --tags --abbrev=0`（若在 git 仓库）
- 再 fallback：abort，要求显式 `$VERSION` 环境变量

**build_artifacts** 产出：
1. `swift build -c release` → `.build/release/<executable>`
2. 多平台交叉编译（arm64 / x86_64 macOS；Linux static binary via Swift cross-compile toolchain）
3. XCFramework（若 `Package.swift` 声明 library product）
4. `.tar.gz` per-platform binary bundle
5. source tarball

**audit_extras**：
- `Package.swift` 版本与 CLI 参数一致（`validate_version_consistency`）
- `Package.resolved` 已提交（依赖版本可复现）
- 无 `import PackagePlugin` 悬挂引用
- binary 通过 `codesign -v`（若 macOS 上 release）
- `SPM` dependency tree 无本地路径依赖（`.package(path:)`）
- 可选：Apple notarization 提交状态

**excluded_from_rsync**：
```
.build/
.swiftpm/
DerivedData/
*.xcuserdata
```

### 签名 / 完整性基础设施（v1.0 一并引入）

- **GPG 签名**：`checksums.txt.asc` 可选产出（`GPG_KEY_ID` 环境变量触发）
- **sigstore** 探索（OIDC-based keyless signing）
- **SBOM 生成**：`syft packages . -o cyclonedx-json` 产出 `sbom.cyclonedx.json`

### 迁移策略

- v0.9.x 的 skill 路径在 v1.0 **不做破坏性变更**
- 新检测逻辑：`release.sh` 遍历 `types/*.sh` 调 `detect`，首个命中即 `$PROJECT_TYPE`
- 多个命中或 0 命中 → abort，要求显式 `PROJECT_TYPE=<type>` 覆盖
- 现有 skill 项目零改动即可继续使用

### v1.0 验收标准

- [ ] `types/skill.sh` 通过现有 17 套件回归
- [ ] `types/spm.sh` 有至少 5 个独立测试套件（detect / version / build / audit / rsync）
- [ ] 至少一个真实 Swift 开源项目成功跑通 release（比如 TKXLAB 自己的 Swift 工具）
- [ ] XCFramework 产物通过 `codesign -v`
- [ ] ROADMAP v1.0 章节标记 ✅ 发布

---

## v1.1+ — Additional Language Plugins

**按优先级排序**（非承诺时间，按实际需求拉）：

| 版本 | 语言 | 关键产物 | 元数据源 |
|------|------|---------|---------|
| v1.1 | **Rust** | 多平台二进制 tarball + `.crate` | `Cargo.toml [package].version` |
| v1.2 | **Go** | `GOOS/GOARCH` 矩阵二进制 | git tag + `go.mod` module path |
| v1.3 | **Python** | `.whl` (wheel) + `.tar.gz` (sdist) | `pyproject.toml [project].version` |
| v1.x | **C/C++** | `cmake --install` prefix tarball | `CMakeLists.txt project(VERSION ...)` |
| v1.x | **Node.js** | `npm pack` tarball | `package.json version` |

每个插件都要遵守 **v1.0 定义的接口契约**，避免插件间漂移。

---

## v2.0 — Release Registry Publishing（探索中，未承诺）

当前 TKX policy §10.10 明确 **从不自动 tag / push / 推 registry**。v2.0 探索"用户显式 opt-in"模型：

- `--publish-to cargo` / `--publish-to pypi` / `--publish-to notarize` 等显式 flag
- Token 走 `vault://` 或 `$ENV_VAR` 引用，**绝不硬编码**
- 每个 registry 都有专属 `audit` 章节确保 metadata 合规后才允许推

如果 TKX policy 不改，这层永远不做；如果社区需求强烈，再设计 opt-in 契约。

---

## 不在路线图内（明确不做）

- **自动生成 changelog** — Keep a Changelog 的 Why 值由人写，机器自动生成反而丢信息
- **自动 git tag / push** — 违反 TKX §10.10 "silent ghost release 护城河"
- **与 CI 平台耦合**（除了提供 `ci.yml` 模板）— 管线本身要能本地跑通，CI 只是调度器
- **GUI / Web 控制台** — 纯 CLI，保持管线可审计

---

## 如何贡献路线图

- **新增 PROJECT_TYPE 提议**：请先开 issue 讨论，附真实项目链接 + 该生态标准产物格式调研
- **跳版本号**：版本号按语义化严格递增（参考 SemVer），新能力必须有测试 + ROADMAP 条目 + CHANGELOG 条目
- **规划与承诺的区别**：ROADMAP 条目**不是**合同；实际版本内容以 CHANGELOG + release tag 为准

路线图本身的变更也走 PR 评审，并在 CHANGELOG 里留下 `### Planning` 段记录。
