# 移植完整性审计（对照原版，除 FMX 外）

对照 `c:\111\ccr\Markdown4D`（Delphi 版）逐单元、逐公开接口核对。日期：2026-11-08。

## 总体结论

| 层 | 状态 |
|----|------|
| `Source/Core`（48 单元） | ✅ **完整**。逐文件名比对 0 差异（机械移植，`Source/Orig` 同源） |
| `Source/Layout`（60 单元） | ✅ **完整**。逐文件名比对 0 差异 |
| VCL → LCL 控件层 | ✅ 主体功能等价（右键菜单、AutoScroll、查找选项、CopyAsMarkdown、Undo/Redo、Zoom/OnScroll、实时预览均已补齐）；仍缺远程图片下载等少数项（下详） |
| 字体资源 / 测试 / 示例 | ❌ 未带过来（下详） |

也就是说：解析器、布局引擎、全部扩展（Alerts/Chart/Mermaid/Math/Toc/Gfm）、HTML 渲染器、写回器、编辑器模型等**库本体没有缺口**；所有缺口集中在"框架粘合层"和外围交付物。

---

## 1. LCL 控件缺失的功能（按影响排序；1.2–1.7 已补齐）

### 1.1 远程图片下载（影响最大，仍未补齐）

原版 VCL viewer 内置 `Markdown4D.Viewer.ImageDownloader`（后台线程 + 大小/域限制），配合 `Images` 属性：

- `Images: TMarkdownViewerImageSettings` —— `BaseUrl`、`AllowRemote`（默认 True）、`MaxBytes`、`RestrictToDocumentFolder`
- `OnRemoteImageRequest(Sender; const Url; var Allow: Boolean)` —— 放行/拦截远程请求

LCL 版**两者都没有**：`http(s)://` 图片一律显示占位框，只能靠 `OnResolveImage` 应用层自供。
注意：`Viewer.ImageDownloader` 单元本身**已移植且能编译**（在 Layout 目录里），只是没接进 LCL viewer。补齐工作量中等（异步线程回调到主线程刷新）。

### 1.2 右键菜单 ✅ 已补齐

原版有现成的菜单构建器（已移植、未接线）：

- `Viewer.ContextMenu`：Copy / Copy as Markdown（Ctrl+Shift+C）/ Select All，按选区状态启停
- `Editor.ContextMenu`：Undo / Redo / Cut / Copy / Paste / Delete Selection / Select All

LCL viewer/editor 现都在 `DoContextPopup` 里接线：宿主赋了 `PopupMenu` 则完全让位；否则用共享构建器（`TMarkdownViewerContextMenu` / `TMarkdownEditorContextMenu`）填充 `TPopupMenu` 并以 `Tag` 分发命令。Ctrl+Shift+C 的"复制为 Markdown"也一并接好。

### 1.3 编辑器↔查看器实时预览集成

原版 VCL editor 内置：

- `Preview: TMarkdownViewer` 属性 + `AttachPreview/DetachPreview/FlushPreview`
- `SyncScroll: Boolean` + `OnSyncScroll(Sender; const SourceLine: Integer)` —— 光标行→预览滚动同步
- 支撑单元 `Editor.PreviewPacer`（节流）与 `Editor.PreviewScroll`（映射，已移植未接线）

LCL editor 现已带完整 API：`Preview: TMarkdownViewer` 属性 + `AttachPreview / DetachPreview / FlushPreview`、`SyncScroll`（默认 True）双向滚动同步、`OnSyncScroll(Sender; SourceLine)`、`TryAdoptPreviewSelection`（预览选区→编辑器源码选区）。更新走 `TMarkdownPreviewPacer` 节流（60ms–1.5s 随上次排版耗时自适应）。demo 里的手写联动可改用官方 API。

### 1.4 AutoScroll（中键平移滚动）

原版 viewer/editor 都支持中键按住进入平移滚动，`AutoScroll: Boolean`（默认 True）、`OnAutoScrollChange`、`IsAutoScrolling`。
支撑单元 `Layout.AutoScroll`、`.AutoScroll.Icon`、`.AutoScroll.Cursors` **全部已移植可编译**。已新建 `Markdown4D.Lcl.AutoScroll`（VCL 版的 LCL 对应物：计时器 16ms 步进、鼠标捕获、死区/切换语义一致；光标在 Windows 用真 pan 光标，其它 widgetset 回退 `crSizeNS`）。viewer 与 editor 均已接：中键开始、任意键/滚轮/点击结束，`AutoScroll` 属性、`IsAutoScrolling`、`OnAutoScrollChange`。右键结束 autoscroll 时会抑制当次菜单。

### 1.5 查找选项（TMarkdownFindOptions）

原版查找 API 带选项重载（区分大小写等）：`FindText(Needle, Options)`、`FindPrevious(Options)`、`FindMatchCount(Options)`、`FindMatchIndex(Options)`、`HighlightMatches(Options)`。
模型层支持完整（`MatchIndex(Needle, Options)` 已移植）。✅ 已补齐：LCL viewer 现有 `FindText / FindPrevious / FindMatchCount / FindMatchIndex / HighlightMatches` 的带 `TMarkdownFindOptions` 重载（区分大小写、整词）。注意：查找只在**可选中**的显示 run 上进行（普通文本、标题、代码块等；强调/斜体 run 所在片段由其所属文本 run 覆盖）。

### 1.6 "复制为 Markdown" 与源码段落

- `CopyAsMarkdown: Boolean` 属性（默认 True，控制 Ctrl+C 行为）+ `CopySelectionAsMarkdown` 方法 + 右键命令
- `TryGetSelectionSourceSegment(out Segment: TMarkdownSegment)` —— 选区对应的原始源码片段（含行号）。**模型方法已移植**（`Viewer.Model` 220 行），LCL viewer 未暴露

✅ 已补齐：viewer 现有 `CopyAsMarkdown: Boolean`（默认 True，控制 Ctrl+C/Ctrl+Shift+C 与菜单项）、`CopySelectionAsMarkdown`、`TryGetSelectionSourceSegment(out Segment: TMarkdownSegment)`；editor 侧 `TryAdoptPreviewSelection` 消费该 API。注意 `SelectedMarkdown` 是**由选区重建**的 markdown（分块间距由写回器决定），与原文逐字节对比时不完全一致。

### 1.7 编辑器公开 API 缺口（大部分已补齐）

已补齐：`Undo / Redo / CanUndo / CanRedo`、`InsertText / PasteFromClipboard / CopyToClipboard / CutToClipboard / SelectAll / SelectedText`、`Zoom` 属性 + `ZoomIn / ZoomOut / ResetZoom / ApplyZoomNow` + `OnZoomChange`（Ctrl+滚轮、Ctrl+加/减/0，滚轮静止 150ms 后重排）、`OnScroll`、`FirstVisibleSourceLine`、`ScrollToSourceLine`。

仍缺（VCL 有而 LCL 无）：

- `ExecuteCommand(TEditorCommand)` 统一命令入口
- `MergeText(Value)`（合并式替换，撤销历史不炸）
- `SaveEditState / LoadEditState`（`IMarkdownEditorState`，跨撤销栈保存恢复）
- `DeleteWordLeft`、公开的 `Indent / Outdent`

### 1.8 查看器小项（仍未补齐）

- ~~公开 `ContentHeight`~~（✅ 已公开，view-only demo 在用）
- 公开 `ZoomIn / ZoomOut / ResetZoom`（LCL 可用 `Zoom` 属性替代，缺便捷方法）
- `CopySelectionToClipboard` 公开方法（LCL 有 Ctrl+C 处理，无方法）

---

## 2. 绘制后端的有意差异（VCL 独有能力）

| VCL | LCL 现状 | 影响 |
|-----|----------|------|
| `TMarkdownTextRendering = (Gdi, DirectWrite)` 双后端，DirectWrite 做 shaping | 仅 `TextOut` 单路径 | 无 kerning/OpenType 特性（连字等）；日常文档观感几乎无差，紧密排版的西文会稍有不同 |
| GDI alpha blend 半透明叠层（选区、搜索标记盖在文字上） | 画在文字**下方**作底色 | 代码块内的选区/标记被块背景遮住（LCL 画布无 alpha 的根本限制） |
| `Vcl.ScrollBar` + `Vcl.ScrollBarTheme`（UxTheme `DarkMode_Explorer`，暗色滚动条） | 原生 `TScrollBar` | 暗色主题下滚动条仍是系统亮色，观感不配套 |
| 行内代码/`<code>` 字号固定为 `CodeFont` 原尺寸（标题里会掉回正文大小，原版行为） | **已修正**：`ScaledCodeFont` 保持代码字体族，但按"代码字号/基础字号"比例跟随所在行字号 | 标题里的 `code` 与标题等大（与 GitHub 等主流渲染一致）；与原版输出不同，属有意修正 |

---

## 3. 数学字体未随包分发

原版 `Source/Fonts/` 带 **STIX Two Math**（OFL 协议 + `.rc/.res` 资源），`Vcl.MathFont.InstallBundledMathFont` 把它注册为安装器，没有 Cambria Math 的系统也能渲染公式。

移植版：字体文件、资源、安装器**都没带**。`Math.Font` 的回退链变成——注册了安装器用注册的，否则按名字请求 `Cambria Math`（Windows 自带，Linux 无）。**有数学公式的文档在 Linux 上会退化为普通字体**。补齐 = 拷字体 + 把 `.res` 换成 LCL 资源或运行时 `AddFontMemResourceEx` 等价物 + 注册安装器。

---

## 4. 测试未移植

原版 `Tests/` 有 **112 个 DUnitX 测试文件**（Editor.Model、Editor.Keys、Folding、Highligher、AutoScroll、Benchmarks 等全套单测 + 性能基准）。

移植版用**规范符合性测试**替代：CommonMark 0.31.2（652）+ GFM 0.29（24）= 676/676，外加 3 个自写 LCL 行为测试（painter 9 项、viewer 15 项、editor 10 项）。核心逻辑的覆盖面主要靠规范套件，但原版对编辑器模型/按键/折叠等**控件逻辑的单测没有对应物**——DUnitX→FPCUnit（Lazarus 自带）是可行的后续工作，且这些测试文件测的是已 1:1 移植的单元，理论上大部分能直接转。

---

## 5. 示例未移植

原版 `Examples/`（Markdown4DStudioVCL、StreamingMarkdownVCL、Showcase、Shared）未移植。移植版 `demo/` 是替代品（左编辑右预览），但**没有**原版 Studio 的工具栏（加粗/斜体/表格插入等编辑辅助）。属可选补齐。

---

## 6. 已接线、功能等价的部分（无缺口）

- `Vcl.Painter` → `Lcl.Painter`（测量、字形、楔形/图表、图片、占位框全部有 LCL 实现）
- `Vcl.ImageDecoder` → `Lcl.Images`（PNG/JPG + SVG 栅格化 + alpha 展平）
- `Vcl.ScrollBar` 的功能（内容/页面/位置同步）→ 原生 `TScrollBar`
- `Vcl.Register` → `Lcl.Register`
- `Vcl.DirectWriteText` 的测量职责 → 离屏画布 `TTextMetric`（行高/基线语义一致）
- 编辑器模型/行布局/高亮/按键/动作/折叠 → 1:1 移植，LCL editor 是外壳
- 查看器模型/显示列表/命中测试/文本查找/点击判定 → 1:1 移植，LCL viewer 是外壳
- `AppendMarkdown`（含节流、自动跟随）→ 已补齐并测试
- 右键菜单 / AutoScroll / 查找选项 / CopyAsMarkdown / 源码段 / 编辑器 Undo-Redo-Zoom-OnScroll / 实时预览集成 → 已补齐并测试（见第 1 节）

---

## 建议的补齐顺序（更新）

原 1–7 项已全部完成。剩余可选项，按影响排序：

1. **远程图片下载**（中——`Viewer.ImageDownloader` 单元已在，接后台线程 + 主线程刷新即可）
2. 编辑器剩余命令 API：`ExecuteCommand / MergeText / SaveEditState / LoadEditState / DeleteWordLeft / Indent / Outdent`（小-中）
3. 查看器小项：`ZoomIn/ZoomOut/ResetZoom` 便捷方法、`CopySelectionToClipboard`（小；`ContentHeight` 已公开）
4. STIX 数学字体随包（Linux 公式渲染退化问题）
5. DUnitX → FPCUnit 单测移植
8. **远程图片下载 + ImageSettings**（中，需线程回调主线程）
9. **STIX Two Math 字体分发**（中，跨平台资源加载要试）
10. **DUnitX→FPCUnit 测试移植**（大，可选）
