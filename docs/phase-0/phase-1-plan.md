# Phase 1 实施计划（待批准）

前提：用户审核 Phase 0 报告后，才进入 Phase 1。Phase 1 不实现阅读器，只建可启动、可导入、可持久化的产品骨架。

## 0. 开工门槛

必须先解决或由用户明确接受：

1. **P0 构建路径**：仓库迁移到 ASCII 路径，或固化 ASCII 构建副本脚本/CI。
2. **P0 Android 运行验证**：至少一台 Android 真机安装 APK，验证 PDF 渲染、PDF 文本选择、TTS 声音枚举三项。
3. 确认 Phase 2 的 EPUB 生产引擎路线（Readium / epub.js / 自增强引擎），避免 Phase 1 后返工。

如果上述 P0 未关闭，只有用户明确批准“并行补验证”时，Phase 1 才可以先做基础设施；Android 运行项仍保持未完成，不能通过 Phase 1 验收。

## 1. 目标

Windows 与 Android 均可启动；导入、保存、删除、重新打开书籍；书库数据持久化；基础主题与模块化架构；不做完整阅读器、不做标注 UI、不做备份。

## 2. 工作包

### P1-1 工程与构建

- 新建 V1 根目录结构（复用推荐架构，不复制 Lab 页面）。
- 固定 Flutter 3.47.9 / Dart 3.13.7 / JDK 17 / Android SDK 36 版本。
- 增加 `scripts/check_env`：Flutter、VS C++、NuGet、Android SDK、ASCII 路径检查。
- Windows debug/release 构建脚本；Android ASCII 构建脚本。
- CI 或本地一键流水线：analyze + unit test + build。

验收：干净环境可复现 Windows 构建与 Android APK；路径检查在中文路径时明确失败而不是构建到一半失败。

### P1-2 SQLite 与迁移

- 选定 `drift` 或 `sqlite3 + DAO`，先做一个最小竖切。
- schema v1：books、shelves、book_shelves、tags、book_tags、reading_progress、settings、attachments。
- `schema_version` 表与迁移执行器。
- 唯一 ID（UUID/ULID），不使用文件名作主键。
- 数据库打开失败不得继续写入。

验收：迁移 v0→v1、关闭重开、事务回滚测试；删除书籍不误删其他表。

### P1-3 文件仓库与导入

- 应用私有目录初始化：database/books/covers/attachments/cache/logs。
- 导入时复制原书到 `books/`，计算 SHA-256，生成书籍 ID。
- 提取基础元数据：标题、作者、格式、文件大小。
- 重复检测：哈希相同 → 提示已存在；同书名不同哈希 → 允许并存。
- 删除书籍：确认对话框；默认不删标注/笔记，除非用户明确选择。

验收：导入 PDF/EPUB/DOCX/TXT/MD 各 1 个；移动外部原文件后应用内仍可打开；删除确认生效。

### P1-4 书库 UI

- Windows：NavigationRail + 书库网格/列表；Android：底部导航 + 网格。
- 最近阅读、最近导入、阅读状态筛选。
- 搜索：书名/作者（先做数据库 LIKE；全文搜索留 Phase 2/3）。
- 封面占位；封面提取可在 Phase 1 先做 PDF/EPUB，DOCX 可选。
- 空状态、错误状态、加载状态。

验收：100 本假数据/50 本真实文件不崩；列表滚动无明显卡顿；删除后列表立即更新。

### P1-5 主题与响应式

- 统一颜色、间距、圆角、字号 token。
- Windows 三栏骨架；Android 五 Tab 骨架。
- 桌面键盘焦点、最小窗口尺寸；手机安全区。
- 明暗主题可切换（至少骨架支持）。

验收：两个平台截图/人工检查；无溢出；中文/英文长标题不破版。

### P1-6 基础测试

- DB 迁移/事务/删除测试。
- 文件复制/哈希/重复检测测试。
- 导入→关闭→重开的集成测试。
- Windows 集成测试；Android 真机冒烟。

## 3. 不在 Phase 1 范围

- PDF/EPUB/DOCX 阅读器 UI。
- 标注、知识仓库、TTS、统计、备份。
- OCR、AI、云同步。
- 正式安装包签名与发布流程（Phase 6）。

## 4. 交付物

- 可运行 Windows/Android 应用。
- SQLite schema v1 与迁移说明。
- 导入/删除/重开测试报告。
- 更新 `README.md`、`docs/architecture.md`、`docs/database.md`。
- 已知问题清单。
- Git 提交（建议至少 3 个：scaffold、database、library）。

## 5. 建议顺序

```text
P1-1 工程/构建 → P1-2 DB 竖切 → P1-3 导入/文件仓库
→ P1-4 书库 UI → P1-5 主题响应式 → P1-6 测试收口
```

不要先做漂亮书库再补数据库；数据安全优先于视觉。

## 6. Phase 1 验收判定

- [ ] Windows 启动
- [ ] Android 真机启动
- [ ] 导入 5 种格式
- [ ] 关闭重开数据仍在
- [ ] 删除书籍有确认，未误删其他书籍/标注
- [ ] SQLite 迁移测试通过
- [ ] 中文路径/ASCII 构建策略已落地
- [ ] 集成测试报告已提交
