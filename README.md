# 墨页 MOYE

Windows + Android 的本地优先数字阅读与个人知识管理软件。

当前仓库已具备 **Phase 1 书库、Phase 2 PDF/EPUB 阅读**，并完成 `.moye` 备份/恢复、系统 TTS、书签与跨书知识仓库的最小 V1 收尾。Windows 端已完成真实 UI 验收；Android APK 已构建，但真机运行验收尚未完成。本文不把“APK 构建成功”写成“Android 端验收通过”。

第一次使用请直接看 **[使用指南](使用指南.md)**：包含 Windows/Android 安装、导入、PDF/EPUB 阅读、朗读、书签、备份恢复和更新方式。

## 当前状态

| 能力 | Windows | Android |
|---|---|---|
| Flutter 构建 | 已通过 | 已通过（必须使用 ASCII 构建路径） |
| 本地 SQLite | 已通过真实导入/重开/删除 | APK 已包含 `libsqlite3.so`，运行未验证 |
| 真实文件导入 | 已通过真实 PDF UI 集成测试 | 代码已接入 SAF 流式读取，运行未验证 |
| 书库列表/搜索/筛选/排序 | 已通过 | 构建通过，运行未验证 |
| PDF 阅读 / 页码恢复 | 已通过真实 UI 集成测试 | 构建通过，运行未验证 |
| EPUB 阅读 / 目录 / 章节位置 / 字体背景 | 已通过真实 UI 集成测试（自建解析器，CSS 有限） | 构建通过，运行未验证 |
| EPUB 空 titlepage / 返回 | 已修复并用 149 章真实 EPUB 回归 | 构建通过，运行未验证 |
| 区域标记 / 备注 / 本书仓库 | 已通过真实 UI 集成测试 | 构建通过，运行未验证 |
| 系统 TTS / 朗读进度 | 已通过真实 UI 集成测试（面板与队列） | 构建通过，运行未验证 |
| `.moye` 备份 / 恢复 | 已通过服务层测试 | 构建通过，运行未验证 |
| 书签 / 跨书知识仓库 | 已通过测试 | 构建通过，运行未验证 |
| 最近阅读时间刷新 / 手动状态 | 已修复并测试 | 构建通过，运行未验证 |
| 书籍详情/状态/删除 | 已通过 | 构建通过，运行未验证 |
| 手机布局 | 390×844 Widget 测试通过 | 构建通过，运行未验证 |

> **Android 运行阻塞**：当前主机没有 Android 真机；模拟器所需硬件虚拟化未启用，ADB server 在本机启动会挂起。详见 [Phase 1 报告](docs/phase-1/PHASE_1_REPORT.md) 与 [Phase 0 环境报告](docs/phase-0/environment.md)。

## 已实现（Phase 1）

- Flutter 应用骨架，Windows / Android 双平台工程。
- Riverpod 依赖注入、go_router 路由、Material 3 明暗主题、中文本地化。
- SQLite schema v5、版本化迁移、外键、WAL、事务。
- 应用私有目录布局；数据库只存相对 POSIX 路径，为后续 `.moye` 迁移做准备。
- 真实文件导入：PDF / EPUB / DOCX / DOC / TXT / Markdown。
- 文件流式复制、边复制边计算 SHA-256、重复检测与缺失文件修复、EPUB/DOCX 容器元数据提取（PDF 及其他格式回退文件名）、阅读进度初始化。
- 真实封面提取：PDF 渲染第一页，EPUB 读取封面图，DOCX 读取首个内嵌图片；统一裁切/压缩为 JPEG 缓存到 `covers/`。旧书在启动后自动补齐封面。
- Phase 2 PDF 阅读器（PDFium）、页码/阅读进度保存与恢复、从书库详情进入阅读。
- Phase 2 EPUB 阅读切片：自建 EPUB 解析器、章节/TOC、字号/行距/背景、章节与块级位置恢复、EPUB 设置持久化。
- 区域标记：阅读器右下角浮标进入框选，拖长方形截取画面并写备注；保存到本书标记仓库，可按备注搜索，阅读器内也显示标记框。
- 系统 TTS：EPUB/PDF 句子级朗读、声音/语速、播放暂停、章节/页码跟随。
- 书签：PDF/EPUB 统一书签面板；底部“标记”提供跨书知识仓库。
- `.moye` 备份/恢复：完整性校验、启动前替换和失败回滚。
- 删除书籍可选保留区域标记到跨书知识仓库。
- 书库：空状态、网格/列表、搜索、状态筛选、排序、导入进度、详情、状态修改、删除确认。
- 删除采用“先隔离文件、再删数据库、失败恢复”的顺序；启动时扫描隔离区，恢复崩溃窗口中的书籍文件。
- Windows 真实 UI 集成测试：导入真实 PDF → 卡片出现 → 关闭重开仍存在 → 详情删除 → 私有文件消失。

明确尚未实现：独立笔记、书架/标签、阅读统计、完整 EPUB CSS/复杂脚注/跨节点 CFI。`.moye` 备份/恢复已实现，详见 [备份设计](docs/backup.md)。DOCX 阅读器按范围决定不做；DOCX 仍可导入。

## 从源码构建

仓库只包含源码，**不包含** Flutter SDK、JDK、Android SDK、Visual Studio 或 NuGet。第一次构建需要联网下载 Dart、Gradle 和 Maven 依赖。

### 环境要求

| 组件 | 要求 |
|---|---|
| Flutter | 3.47.9 stable（Dart 3.13.7）已实测；`pubspec.yaml` 要求 Dart `^3.13.7` |
| Windows | Visual Studio 2022，安装“使用 C++ 的桌面开发”和 Windows 10/11 SDK；建议开启 Windows 开发者模式（pdfrx 的 native assets 使用符号链接） |
| Android | JDK 17；Android SDK Platform 36、Build-Tools 36.0.0、NDK 28.2.13676358；已接受 SDK licenses |
| NuGet CLI | Windows 构建 `flutter_tts` 需要 |
| 路径 | Android 必须使用**纯 ASCII 路径**；中文或全角字符路径会导致 Gradle/NDK 中间产物缺失 |

安装完成后先运行 `flutter doctor -v`，确认 Windows 桌面和 Android 工具链均通过。详细版本记录见 [环境报告](docs/phase-0/environment.md)。

### Windows

```powershell
git clone https://github.com/qingfu7036/moye.git
cd moye
flutter pub get
dart analyze lib test integration_test
flutter test
flutter build windows --release

# 产物：build\windows\x64\runner\Release\moye.exe
```

`flutter analyze` 在含中文的路径下可能因 analysis server 崩溃返回 255；这是工具链限制，改用上面的 `dart analyze`。

### Android

```bash
# 必须使用纯 ASCII 路径，例如 C:\dev\moye
git clone https://github.com/qingfu7036/moye.git /c/dev/moye
cd /c/dev/moye
flutter pub get
flutter build apk --debug

# 产物：build/app/outputs/flutter-apk/app-debug.apk
```

Android 首次构建在验证机上约 13–14 分钟，主要耗时在 Gradle/Maven 下载和原生库编译，具体取决于网络。debug APK 约 192 MB（包含三套 ABI），release APK 约 88 MB。**构建成功不等于 Android 真机验收通过**；当前仍未完成真机运行验证。

### 干净 clone 验证记录

2026-11-22，在纯 ASCII 目录重新 clone commit `f87b780` 后实测：

- `flutter pub get` 成功；`dart analyze lib test integration_test` 为 0 问题。
- `flutter test`：42 个测试全部通过。
- `flutter build windows --release`：154 秒构建成功。
- `flutter build apk --debug`：成功生成约 192 MB 的 APK，ZIP 结构校验通过。

这次验证只证明“新环境可以下载、编译和测试”，不代表 Android 真机运行已经验收。

### SQLite 的 Android 构建说明

Android 的 `abiFilters` 固定为 `arm64-v8a`、`armeabi-v7a`、`x86_64`；APK 内三套 ABI 都有 `libflutter.so` 与 `libsqlite3.so`。`zipalign -c -P 16` 已通过，64 位库 LOAD 对齐为 `0x4000`。

`package:sqlite3` 3.8 默认从 GitHub 下载预编译 Android `.so`。本机到 GitHub 超时，因此 Android 使用 Maven Central 的 `eu.simonbinder:sqlite3-native-library:3.50.4` AAR 提供 `libsqlite3.so`；`pubspec.yaml` 的 hook 仅在 Android 使用 `source: system`，Windows 仍使用包默认原生资产。

这不是运行时降级：APK 内确实包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三套 `libsqlite3.so`。但 Android 运行期数据库打开**尚未在真机/模拟器验证**。

## 数据位置

Windows：

```text
%APPDATA%\app.moye\moye\
├── database\library.db
├── books\
├── covers\
├── attachments\
├── cache\trash\
├── backups\
└── logs\
```

Android 使用 `path_provider` 的应用私有目录，布局相同。数据库不保存绝对路径；书籍文件通过 `books/<uuid>.<ext>` 相对路径引用。详见 [数据库设计](docs/database.md)。

## 文档

- [Phase 1 验收报告](docs/phase-1/PHASE_1_REPORT.md) — Windows 验收、Android 构建、限制与下一步
- [Phase 2 进度](docs/phase-2/PHASE_2_PROGRESS.md) — PDF 阅读器、页码恢复、下一步
- [系统语音朗读](docs/tts.md)
- [`.moye` 备份与恢复](docs/backup.md)
- [Phase 2 验收标准](docs/phase-2/PHASE_2_ACCEPTANCE.md) — PDF/EPUB、搜索、位置恢复、跨平台门禁
- [数据库设计](docs/database.md) — schema v5、区域标记、导入/删除一致性、迁移规则
- [区域标记与本书仓库](docs/annotations.md) — 框选、截屏、备注、搜索与阅读器内标记
- [Phase 0 总报告](docs/phase-0/PHASE_0_REPORT.md) — 技术验证、风险、架构建议
- [环境报告](docs/phase-0/environment.md)
- [技术选型报告](docs/phase-0/technical-selection.md)
- [插件兼容性报告](docs/phase-0/plugin-compatibility.md)
- [风险清单](docs/phase-0/risk-register.md)
- [推荐架构](docs/phase-0/architecture-recommendation.md)
- [定位与标注设计](docs/phase-0/locator-design.md)
- [Phase 0 测试报告](docs/phase-0/test-report.md)
- [Phase 1 实施计划](docs/phase-0/phase-1-plan.md)

## Phase 0 原型

`spikes/phase0_lab` 保留为风险验证实验室：PDFium 渲染与文字坐标、EPUB CFI、DOCX 结构、系统 TTS。它使用真实测试样书，不依赖假数据。

## Windows 快捷方式

桌面快捷方式和 `Ctrl+Alt+M` 全局快捷键由脚本创建：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\create_windows_shortcut.ps1
```

快捷方式指向稳定的 `dist\MOYE-Windows\moye.exe`。以后原地重新构建 `dist` 时，快捷方式、热键和内嵌图标仍然有效；只有移动整个程序目录时才需要重新运行脚本。

图标母版在 `assets/branding/moye_icon_1024.png`，可用 `scripts/generate_app_icons.py` 重新生成 Windows `.ico` 和 Android 各密度图标。

## 产物

- Windows 调试构建：`build/windows/x64/runner/Debug/moye.exe`
- Android Debug APK（Phase 2 / schema v5）：`artifacts/phase-2/moye-phase2-schema5-debug.apk`
- Android Release APK（约 88 MB）：`artifacts/phase-2/moye-phase2-schema5-release.apk`
- APK SHA-256：`artifacts/phase-2/SHA256SUMS.txt`、`artifacts/phase-2/SHA256SUMS-release.txt`
- Phase 0 原型：`spikes/phase0_lab`

Debug APK 是通用包，包含三套 ABI；Release APK 是当前更小的安装包。两者都不代表最终渠道包体积。

## 状态与下一步

- Phase 0：可执行部分已完成，报告已归档。
- Phase 1：Windows 可执行验收通过；Android 构建通过、运行待验证。**等待用户真机验收后再确认关闭。**
- 进入 Phase 2 前，建议先完成 Android 真机上的启动、导入、重开、删除；若无法完成，需由用户明确接受“仅构建验证”的风险。
- Phase 2 的第一切片应是“打开已导入 PDF → 渲染 → 恢复位置 → 关闭重开仍恢复”，不要同时混入标注或 TTS。

## 许可

本项目采用 [MIT 许可证](LICENSE)，Copyright (c) 2026 qingfu7036。你可以自由使用、修改和再分发，只需保留版权与许可声明。

---

CHANGELOG 见 [CHANGELOG.md](CHANGELOG.md)。
