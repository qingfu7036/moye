# Phase 2 进度：PDF + EPUB 阅读切片

日期：2026-11-06（2026-11-07 更新 PDF 目录/页码跳转、PDF/EPUB 书内搜索；2026-11-08 完成 PDF 页内位置恢复与 PDF 缩放持久化、EPUB 内部链接/基础脚注、合并单元格/嵌套表与 ruby，移除文字选择/复制）
版本：1.4.0+8
状态：**Windows 端 PDF 与 EPUB 阅读切片、PDF 目录/页码跳转、PDF 页内位置恢复与缩放持久化、PDF/EPUB 书内搜索、EPUB 内部链接/基础脚注/基础表格/ruby、区域标记与本书仓库、全局知识仓库、书签、系统 TTS 最小朗读与 speech_progress 通过；Android 构建通过、运行未验证；PDF 文字选择/复制已按用户决定移除，完整 EPUB CSS 和双页/连续滚动等统一设置仍未完成。DOCX 阅读器已按用户范围决定不做。**

## 1. 本切片交付

- 使用 PDFium（`pdfrx`）在 Windows 上打开真实 PDF。
- 从书库详情点击“开始阅读”进入 PDF/EPUB 阅读器。
- EPUB：自建解析器、章节目录、章节切换、整体缩放（文字+图片）、书内关键词搜索（结果计数、上一处/下一处、命中跳转与高亮）、内部链接/基础脚注（脚注目标文本弹窗）、基础表格（表头/行列/横向滚动/colspan/rowspan）、嵌套表内容扁平化、ruby 注音、字号/行距/段间距/背景、章内块位置恢复、设置持久化。
- PDF：目录（outline）加载与层级跳转、点击页码输入跳转、页内滚动偏移恢复、书内关键词搜索（结果计数、上一处/下一处、命中跳转与高亮）、滚动/缩放、缩放比例持久化、适应宽度/适应页面。文字选择/复制按用户决定移除。
- 区域标记：PDF/EPUB 阅读器框选截图、备注、本书标记仓库、全局知识仓库、按备注搜索、阅读器内标记框。
- 书签：PDF 页码/页内偏移、EPUB 章节/块，统一书签面板可跳转和删除。
- TTS：系统声音/语速、播放/暂停/停止、逐句朗读、EPUB 跨章跟随与段落高亮、PDF 当前页起自动加载下一页、`speech_progress` 独立保存。
- 页码指示、PDF 缩放设置（滑杆、适应宽度/页面并持久化）、EPUB 字号/行距/段间距/背景、返回书库。
- 阅读位置写入 `reading_progress.anchor_json`：`{"page": N, "offset": 0.0}`（offset 为页高比例）。
- 再次打开同一本书时恢复到最后页码。
- 返回书库前保存位置；阅读器销毁时兜底保存。
- PDF 封面与阅读器共用 PDFium，避免引入第二套 PDF 引擎。

## 2. 数据层

```text
reading_progress
  book_id       TEXT PRIMARY KEY
  anchor_json   TEXT     -- PDF: {"page": N}
                          -- EPUB: {"chapter": N, "block": N, "cfi": "..."}
  percent       REAL
  mode          TEXT     -- 'pdf' / 'epub'
  updated_at    INTEGER
```

`LibraryRepository.getProgress` / `saveProgress` / `saveEpubProgress` 负责读写；写入使用事务，同时更新 `books.last_opened_at`。

## 3. 验证

```text
dart analyze lib test integration_test
No issues found!

flutter test
00:08 +42: All tests passed!

flutter test integration_test/phase1_library_test.dart -d windows
00:03 +1: All tests passed!

flutter test integration_test/pdf_reader_test.dart -d windows
00:05 +1: All tests passed!

flutter test integration_test/epub_reader_test.dart -d windows
00:06 +1: All tests passed!
```

`epub_reader_test` 实际验证：

- 导入真实 `sample_links.epub`；
- 打开 EPUB 并显示章节/目录；
- 从目录点击章节；
- 打开搜索，输入 `MOYE-EPUB-CFI-ANCHOR`，得到 1 个结果并跳转到第 1 章；
- 搜索 `查看脚注`，点击脚注链接，弹窗显示脚注目标文本并关闭；
- 搜索 `表格渲染`，定位到表格块并渲染行列结构；
- 解析器测试覆盖 `rowspan=2`、`colspan=2`，并确认内层表行不会被误并入外层；
- 搜索 `漢字`，正文显示基准文字与注音 `かんじ`；
- 返回书库；
- 章/块/CFI 锚点写入数据库。

`pdf_reader_test` 实际验证：

- 导入带 outline 的真实 `sample_outline.pdf`；
- 先写入第 2 页、35% 页内偏移的阅读位置；
- 打开详情并点击“开始阅读”；
- `PdfViewer` 成功加载；
- 页码指示显示第 2 页，可见区域恢复到约 35% 页高；
- 预置 150% 缩放，打开后控制器恢复到约 1.5×；
- 工具条不显示文字选择/复制入口；
- 打开目录，点击“第二章 标注定位”后跳转到第 2 页；
- 点击页码，输入 3 并跳转到第 3 页；
- 打开搜索，输入 `MOYE-PHASE0-ANCHOR`，得到 1 个结果并跳转到第 2 页；
- 关闭搜索并返回书库后，书籍仍在，进度记录仍存在。

## 4. 尚未完成

- EPUB 生产引擎决策：当前为自建解析器的**阅读切片**，不是对 Phase 0 “生产引擎未定”结论的最终关闭；需按 10 本真实 EPUB 做引擎对比后再定稿。
- EPUB 完整 CSS、复杂脚注和跨节点 CFI；基础内部链接/脚注/表格/合并单元格/嵌套表/ruby 已支持，复杂排版仍待补齐。
- EPUB 跨节点 CFI/段内精确定位仍为块级锚点。
- PDF 已有缩放比例持久化；EPUB 已有字号/行距/段间距/背景持久化。统一设置面板、双页/连续滚动模式尚未实现。
- PDF 文字选择/复制：按用户决定移除，不纳入当前 V1 阅读切片。
- Android 运行验证（APK 已含 PDFium，未安装到真机）。

## 5. 下一步建议

1. 在 EPUB 生产引擎上继续补齐复杂脚注、完整 CSS 和跨节点 CFI；合并单元格/嵌套表已有基础支持。
2. 统一 PDF/EPUB 阅读设置面板，补齐双页/连续滚动等模式。
3. 在 Android 真机完成 PDF 打开/翻页/缩放/重启恢复后，再宣称跨平台阅读通过。
