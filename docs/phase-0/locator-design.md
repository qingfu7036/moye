# Phase 0 定位与标注设计

日期：2026-11-02
适用：Phase 1/2 的锚点与标注模型。Phase 0 只实现验证子集。

## 1. 设计目标

1. 同一套 `ReadingAnchor` 能表达 PDF、EPUB、DOCX、TXT/Markdown 的位置。
2. 绝不只保存选中字符串。
3. 源文件变化时，优先恢复；无法可靠恢复时明确提示，并保留用户笔记。
4. 阅读位置与听书位置可以共用锚点格式，但独立存储。
5. 点击摘录必须能回到原文；不是只打开书籍第一页。

## 2. 核心模型

Phase 0 实现（`reading_anchor.dart`）：

```dart
enum BookFormat { pdf, epub, docx, txt, markdown }

class ReadingAnchor {
  final BookFormat format;
  final String quote;

  // PDF
  final int? page;             // 1-based
  final int? pageStart;        // 选区起（字符）
  final int? pageEnd;          // 选区止（字符，exclusive）
  final List<PdfRectData> pdfRects; // 页面坐标矩形，可能多行

  // EPUB
  final int? spineIndex;
  final int? blockIndex;
  final String? cfi;

  // DOCX / TXT
  final int? charOffset;
  final String? docxPath;      // body/p[N]

  // 通用校验/重锚定
  final String contextBefore;
  final String contextAfter;
  final String? textHash;
  final String? color;
}
```

V1 建议把 `pageStart/pageEnd` 重命名为 `rangeStart/rangeEnd` 或拆成 `FormatAnchor` sealed class，避免 PDF 语义泄漏到 EPUB/DOCX；Phase 0 为减少代码量保留了通用字段。

### PDF 锚点

```text
page + charStart..charEnd + quote + context
+ rects[]（每行/每个 fragment 一个矩形）
+ pageTextHash
```

- 坐标使用 PDF 页面坐标（左下原点，`top > bottom`），渲染时通过 `toRectInDocument(page, pageRect)` 转屏幕坐标。
- 旋转页必须在 V1 存 rotation；当前 Phase 0 未覆盖旋转。
- 跨页标注应存 `List<PageRange>`，而不是一个 `page` 字段；Phase 0 明确拒绝跨页，留到 Phase 3。

### EPUB 锚点

```text
spineIndex + blockIndex + cfi + charOffset
+ quote + contextBefore/After + chapterTextHash
```

- CFI 用于标准互操作，blockIndex/charOffset 用于当前自建渲染器的快速恢复。
- Phase 0 CFI 为元素级 + 简单文本偏移；复杂内联节点可能不精确。
- 示例：`epubcfi(/6/2[ch1]!/4/2/6/1:4)`，已由 epub.js `EpubCFI` 解析验证。
- 生产 V1 若换成 Readium/epub.js，CFI 由引擎生成；仍保留 quote/context 作为重锚定后备。

### DOCX 锚点

```text
docxPath（body/p[N] 或 body/tbl[N]）
+ charOffset
+ quote + contextBefore/After + documentTextHash
+ styleId（可选）
```

- Phase 0 的 `body/p[20]` 是 body 直接子段落序号；表格内文本需要扩展为 `body/tbl[1]/tr[2]/tc[1]/p[1]`。
- 源文件替换后，先比较文件哈希；再按 `docxPath` 尝试，失败则 quote+context 重锚定。

### TXT / Markdown

```text
charOffset + quote + context + documentTextHash
```

Markdown 需要另存块级结构（标题/段落）时，可增加 `blockIndex`，但字符偏移仍是最终定位。

## 3. 重锚定算法

Phase 0 实现 `Anchoring.find`：

1. 在文档文本中查找所有 quote 出现位置。
2. 对每个候选，比较前文后缀与后文前缀。
3. 结构偏移（charOffset）作为轻微加权，不允许覆盖强上下文。
4. 返回 `confidence`。
5. 低置信度或多候选 → 不静默跳转，提示用户。

判定阈值需在 Phase 3 用真实书籍校准；不要仅凭一次样本把阈值写死。

## 4. 标注生命周期

```text
创建：
选择 → 引擎返回 quote + 格式定位 → 补 context/hash
→ 事务写 annotation → 立即绘制高亮

修改：
改颜色/批注/标签 → 更新 updated_at → 不改变 anchor

删除：
删除前确认；知识库与阅读器共享同一记录
→ 删除后从所有视图移除；不做“阅读器删了但知识库还在”的分裂状态

源文件变化：
文件哈希变化 → 尝试重锚定
→ 成功：更新 anchor，保留 id
→ 失败：orphaned=true，保留 quote/note，提示导出/重新定位

导出：
Markdown/TXT/HTML/JSON 都导出 quote + note + 来源 + 创建时间
+ 可选 anchor 原始 JSON（便于再次导入）
```

## 5. 阅读位置与听书位置

两张独立记录：

```text
reading_progress(book_id, anchor_json, percent, mode, updated_at)
speech_progress(book_id, anchor_json, tts_voice, rate, updated_at)
```

- 阅读位置：最后滚动/页位置、阅读模式、字体字号、主题。
- 听书位置：最后朗读句子锚点、声音、语速。
- 互跳：从听书位置打开阅读器时高亮当前句；从阅读位置开始朗读时从当前段/句开始。
- 关闭应用前必须持久化；崩溃恢复使用最后一次事务提交的位置。

## 6. 当前 Phase 0 的边界

已实现：

- PDF 选区回读、矩形、颜色、JSON 落盘。
- EPUB 段内标注、CFI、字号重排后位置仍由 block+offset 保留。
- DOCX 段落路径 + 字符偏移、标注保存。
- quote + context 重锚定单测。

未完成（不得声称完成）：

- PDF 跨页/旋转/双页标注。
- EPUB 复杂 inline/CSS/脚注的精确 CFI 范围。
- DOCX 表格单元格/页眉页脚的完整路径。
- 源文件替换的真实端到端 UI 测试。
- SQLite 事务与迁移。
- 标注导出 UI。
- OCR。

## 7. 关键测试用例（Phase 3 必测）

1. 同一段文字重复出现 3 次，context 能否选对。
2. EPUB 字号从 16 调到 28，标注是否仍在原句。
3. PDF 旋转 90° 后高亮是否跟随。
4. 源文件被同名替换，标注是恢复、orphaned 还是误跳。
5. 删除书籍时标注/笔记是否按用户选择处理。
6. 导出 Markdown 后重新导入，定位是否可逆。
7. 听书暂停后关闭应用，重新打开是否回到同一句。
