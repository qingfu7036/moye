# Phase 0 风险清单

优先级：P0 阻塞进入 Phase 1 / P1 影响 V1 功能或数据安全 / P2 体验或维护风险。

| ID | 优先级 | 风险 | 现状证据 | 影响 | 缓解方案 | 关闭阶段 |
|---|---|---|---|---|---|---|
| R-01 | P0 | Android 运行验证缺失 | 无真机；模拟器不可用；ADB start-server 挂起 | Android 的 PDF/TTS 能力未被真实证明，不能宣称 Phase 0 全平台通过 | 用户提供 Android 真机，开 USB 调试；安装 APK，执行 PDF 选区、TTS 声音/暂停测试；必要时另装模拟器 | Phase 0 复核 |
| R-02 | P0 | 仓库中文路径导致 Android 构建失败 | 直接 Gradle 构建失败；ASCII 副本成功 | 构建不可复现，CI 无法直接工作 | 仓库迁移至 ASCII 路径，或固定 ASCII 构建副本脚本；不要只依赖 `overridePathCheck` | Phase 1 前 |
| R-03 | P1 | EPUB 生产引擎未定 | 自建解析器只覆盖样例子集；`epubx` 与 pdfrx 冲突 | EPUB3 CSS、脚注、ruby、表格、复杂 CFI 可能无法达 V1 标准 | Phase 2 前单独对比 Readium、epub.js WebView、增强自建引擎；做 10 本真实 EPUB 验收 | Phase 2 |
| R-04 | P1 | 自建 CFI 只覆盖元素级与简单文本偏移 | 示例 CFI 经 epub.js 解析；跨节点范围未做 | 标注在复杂 EPUB 中可能偏移或无法恢复 | 保存 quote + 前后文 + spine + block + charOffset；生产 CFI 交给成熟引擎；异常时提示用户重锚定 | Phase 2 |
| R-05 | P1 | DOCX 保真度不足 | 只保留纯文本、基本标题/列表/表格/图片/链接 | 复杂 Word 文档看起来“掉格式” | 先明确“阅读优先、非 Word 复刻”；补 inline run、合并单元格、页眉页脚、编号样式；大文件 isolate | Phase 2 |
| R-06 | P1 | `.doc` 未支持 | 只识别 DOCX/ZIP | 老文档无法导入 | 检测 `.doc`，提示另存为 DOCX 或集成 LibreOffice headless 转换；不得静默失败 | Phase 1/2 |
| R-07 | P1 | PDF 跨页/旋转/混合页标注未完成 | 原型只保存单页；坐标在 A4 竖版验证 | 双页、横版、旋转页高亮可能错位 | 标注模型改为一组页内 rect；每个 rect 带 page + rotation；做旋转样本验收 | Phase 3 |
| R-08 | P1 | 扫描 PDF 判定是启发式 | 只读前 3 页，按字符数判断 | 封面扫描但正文有文字的 PDF 可能被误判 | 按页记录 `hasTextLayer`，文档级只做提示；允许用户切换/覆盖判定；OCR 作为扩展 | Phase 2 |
| R-09 | P1 | TTS 句子级而非单词级 | Windows 无 word boundary；按句提交 | 无法满足“逐词卡拉 OK”式高亮 | V1 按需求明确句子级；若后续要单词级，Android 用 onRangeStart，Windows 用 SAPI 事件/本地模型时间戳 | Phase 4 |
| R-10 | P1 | Android pause 在 API 24/25 不可用 | flutter_tts 文档说明依赖 API 26+ 的 onRangeStart | 老设备暂停行为异常 | Adapter 版本判断：<26 改为 stop + 从句首重播；UI 明确状态 | Phase 4 |
| R-11 | P1 | 后台/锁屏 TTS 未实现 | 当前仅前台 Flutter 播放 | 锁屏或切后台可能停止 | Android 前台服务 + MediaSession；Windows 音频会话；先做系统允许范围内的实现 | Phase 4 |
| R-12 | P1 | 数据层尚未实现 | Phase 0 仅 JSON 锚点 | 不能进入真实书库/标注/备份 | Phase 1 建 SQLite 迁移、事务、外键、索引；禁止直接沿用 JSON | Phase 1 |
| R-13 | P1 | 备份/恢复未验证 | Phase 5 才做 | 跨设备迁移失败可能损坏数据 | `.moye` 临时目录 + manifest 校验 + 哈希 + 原子替换 + 回滚；做损坏/磁盘不足测试 | Phase 5 |
| R-14 | P1 | 大文件/大书库性能未验证 | 只用 3 页 PDF、2 章 EPUB、23 块 DOCX | 100 本书或数百页 PDF 可能卡顿/OOM | Phase 1/6 做 100 本导入、数百页 PDF、长 EPUB；解析/哈希进 isolate；分页缓存预算 | Phase 1/6 |
| R-15 | P2 | Windows Developer Mode / 管理员符号链接要求 | pdfrx 文档要求；本机靠管理员权限 | 新开发机首次构建失败 | 构建前置检查脚本；文档明确；CI 使用管理员/已启用 Developer Mode 的 runner | Phase 1 |
| R-16 | P2 | `flutter_tts` 未来 Kotlin 兼容警告 | Flutter 构建警告 | 升级 Flutter 后可能构建失败 | 锁 Flutter 3.47.9；Phase 4 评估新版本/fork | Phase 4 |
| R-17 | P2 | `pdfrx` `material_ui` 类型分裂 | PDF 组件与 Flutter Material 类型不同 | 自定义菜单/主题集成成本 | 统一 UI 主题策略；避免混用菜单类型；跟踪 pdfrx 版本 | Phase 2 |
| R-18 | P2 | EPUB/DOCX 解析在主 isolate | 原型直接 `parse()` | 大文件打开时 UI 卡顿/ANR | parse 移入 isolate；大小上限；可取消加载 | Phase 2 |
| R-19 | P2 | 阅读位置恢复未做跨重启真实验收 | EPUB/DOCX 写入 JSON，但没有关闭重启测试 | 可能“看起来保存了但恢复不准” | Phase 2 建立 10 本样书的重启恢复矩阵；PDF 页+坐标、EPUB CFI+charOffset、DOCX path+offset | Phase 2 |
| R-20 | P2 | 中文断句/搜索规则有限 | 规则按标点/换行，未处理所有缩写 | 中英混排句子切分偶发不自然 | 建立中文/英文/混排语料单测；允许手动切换句 | Phase 4 |
| R-21 | P2 | 当前 Lab 启动即初始化所有 Tab | `IndexedStack` 预构建 PDF/TTS | 启动开销、TTS 引擎早初始化 | Phase 1 改懒加载 Tab；TTS 进入阅读器或语音页再初始化 | Phase 1 |
| R-22 | P2 | 依赖网络不稳定 | GitHub/Maven 超时；SDK 下载慢 | 新环境搭建不可预测 | 固化镜像/代理策略；缓存工具链；记录版本锁定 | Phase 1 |
| R-23 | P2 | 许可证与分发 | pdfrx/PDFium/Flutter/flutter_tts 均为宽松许可，但需保留 notices | 发布合规风险 | Phase 6 生成第三方 notices；确认字体/样例版权 | Phase 6 |
| R-24 | P2 | 测试数据包含系统字体生成的 PDF | SimHei 子集嵌入测试 PDF | 不能把测试样书当可分发内容 | 保留在 test fixtures，不进入正式安装包；发布前替换 | Phase 6 |

## 数据安全红线

以下问题在 V1 中属于“发现即优先修复”，不能带入发布：

1. 备份恢复未校验就覆盖当前数据库。
2. 删除书籍时级联删除标注、笔记或阅读记录。
3. 清理缓存时删除 `books/`、`covers/` 或用户附件。
4. 标注只保存字符串，不保存结构定位和上下文。
5. 数据库迁移失败后继续启动并写入。
6. 恢复失败后原数据库已被部分替换。
7. 把完整路径或用户目录写死进数据库/备份，导致跨设备恢复失败。

## 结论

Phase 0 的主要风险不是“代码写不出来”，而是：

- **Android 运行环境未验证**（P0）
- **构建路径不可复现**（P0）
- **EPUB 生产引擎未定**（P1）
- **数据层/备份尚未开始**（P1，按计划）

在这两个 P0 关闭之前，不建议把 Phase 0 标记为“全平台通过”，也不建议直接进入 Phase 1 的正式产品开发。
