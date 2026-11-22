# Markdown4D for Lazarus 使用说明

Lazarus/FPC 版 Markdown 库，提供两个控件：

| 控件 | 单元 | 用途 |
|------|------|------|
| `TMarkdownViewer` | `Markdown4D.Lcl.Viewer` | 渲染 Markdown 文档（标题、列表、表格、代码块、图片、链接、`<details>` 折叠等） |
| `TMarkdownEditor` | `Markdown4D.Lcl.Editor` | 编辑 Markdown 源码（语法着色、行号、折叠、软换行、撤销重做） |

两个控件都只是各自**设备无关模型**的外壳：解析、布局、编辑逻辑在 `Source/Core` 与 `Source/Layout`，绘制统一走 `Source/Lcl` 的 `IPainter` 实现。CommonMark 0.31.2 + GFM 0.29 共 676 个规范用例全部通过。

---

## 1. 安装

### 方式一：安装组件包（推荐）

1. Lazarus 菜单 `Package → Open Package File (.lpk)`，打开 `packages/markdown4d_lcl.lpk`
2. 点击 `Compile` 编译
3. 点击 `Use → Install`，Lazarus 会重新构建 IDE
4. 安装完成后，组件面板出现 **Markdown4D** 页，内有 `TMarkdownViewer` 和 `TMarkdownEditor`

### 方式二：直接引用源码

不装包也可以，把以下目录加入项目的搜索路径（`Project → Project Inspector → Compiler Options → Other unit files`）：

```
Source/Compat; Source/Core; Source/Layout; Source/Lcl
```

然后在 `uses` 里直接引用单元即可。

### 演示程序

`demo/markdown4d_demo.lpi` 是一个左编辑右预览的实时预览程序，用 `lazbuild` 或 IDE 打开即可编译运行，双击 `demo/sample.md` 可换文件。

---

## 2. 快速上手

### 最简单的查看器

```pascal
uses Markdown4D.Lcl.Viewer;

// 运行时创建
Viewer := TMarkdownViewer.Create(Self);
Viewer.Parent := Self;
Viewer.Align := alClient;
Viewer.Text := '# 你好' + LineEnding + LineEnding + '这是 **Markdown** 文本。';
```

### 最简单的编辑器

```pascal
uses Markdown4D.Lcl.Editor;

Editor := TMarkdownEditor.Create(Self);
Editor.Parent := Self;
Editor.Align := alClient;
Editor.Text := '# 标题';
```

### 实时预览

```pascal
procedure TForm1.EditorChange(Sender: TObject);
begin
  Viewer.Text := Editor.Text;
end;
```

参考 `demo/mainform.pas`，其中还包括打开文件、保存文件、同步滚动到光标处的完整做法。

---

## 3. TMarkdownViewer

### 3.1 常用属性（published，可在设计期设置）

| 属性 | 类型 | 说明 |
|------|------|------|
| `Text` | `string` | Markdown 源码。赋值即重新布局 |
| `Zoom` | `Integer` | 缩放百分比（默认 100）。**不是画布变换**：控件用缩放后的主题重新排版，字形位置精确 |
| `ScrollOffset` | `Single` | 视口顶端在文档中的位置（像素），自动钳制在 [0, 最大值] |
| `ThemePreset` | `TMarkdownThemePreset` | 内置主题，`Light` / `Dark` |
| `Theme` | `TMarkdownTheme` | 自定义主题对象（颜色、字体、字号、间距）。控件只在 `ThemePreset` 创建时释放自己建的；赋入的主题由调用方管理 |
| `ContentScale` | `Single` | 整体缩放系数，乘到每个字号和长度上。适合高 DPI 窗体整体缩放，与 `Zoom` 独立 |
| `DocumentFolder` | `string` | 相对路径图片的基准目录，通常设为文档所在目录 |
| `FlushIntervalMilliseconds` | `Cardinal` | `AppendMarkdown` 的合并间隔，默认 100 |

### 3.2 加载内容

```pascal
Viewer.Text := S;                              // 整体替换
Viewer.LoadFromFile('doc.md');                 // 从文件加载
Viewer.LoadFromStream(Stream);                 // 从流加载（UTF-8）
```

### 3.3 按行追加（日志 / 流式输出）

```pascal
Viewer.AppendMarkdown('- 第 1 行' + LineEnding);
Viewer.AppendMarkdown('- 第 2 行' + LineEnding);
```

- 追加先进队列，**每 100ms 合并重排一次**，循环逐行追加不会逐行重排
- 视图停在底部时自动跟随新内容；用户往上滚了则不干扰
- 对实时性有要求可设 `Viewer.FlushIntervalMilliseconds := 0`（下个定时滴答立即刷出）

### 3.4 查找与高亮

```pascal
if Viewer.FindText('关键词') then ...       // 跳到下一个匹配并选中
Viewer.FindPrevious('关键词');               // 反向
N := Viewer.FindMatchCount('关键词');        // 匹配总数
I := Viewer.FindMatchIndex('关键词');        // 当前是第几个匹配
Viewer.HighlightMatches('关键词');           // 全部匹配画高亮底色
Viewer.ClearHighlights;                      // 清除高亮
```

### 3.5 选中与复制

```pascal
Viewer.SelectAll;
S := Viewer.SelectedText;      // 选中区域的渲染文本
M := Viewer.SelectedMarkdown;  // 选中区域的 Markdown 源码
Viewer.ClearSelection;
```

### 3.6 图片

- 本地文件（相对 `DocumentFolder` 解析）与 SVG 自动支持
- 远程图片**不做 HTTP 下载**，需要时用 `OnResolveImage` 自行提供：

```pascal
procedure TForm1.ViewerResolveImage(Sender: TObject; const Url: string;
  const Picture: TPicture; var Handled: Boolean);
begin
  if Url.StartsWith('http') then
  begin
    Picture.LoadFromResourceName(HInstance, 'MY_IMAGE'); // 或自己的缓存/下载
    Handled := True;
  end;
end;
```

- 加载失败的图片显示占位框；`OnExtensionError` 报告扩展（如 Mermaid）渲染错误

### 3.7 链接与锚点

```pascal
procedure TForm1.ViewerLinkClick(Sender: TObject; const Url: string);
begin
  OpenDocument(Url);   // 自己决定怎么打开
end;

Viewer.ScrollToAnchor('getting-started');  // 跳到 #getting-started 对应的标题
```

### 3.8 交互内置行为

- 滚轮滚动、Ctrl+滚轮缩放、拖拽选择、双击选词、三击选行
- 键盘：方向键/PgUp/PgDn 翻页，Ctrl+A 全选，Ctrl+C 复制，Ctrl+Home/End
- 代码块悬停显示复制按钮；`<details>` 折叠标记可点击展开/收起
- 链接悬停触发 `OnLinkHover`，状态栏提示可配合使用

### 3.9 事件一览

| 事件 | 签名 | 触发时机 |
|------|------|----------|
| `OnLinkClick` | `(Sender; const Url: string)` | 点击链接 |
| `OnLinkHover` | `(Sender; const Url: string)` | 悬停链接（离开时 Url 为空） |
| `OnResolveImage` | `(Sender; const Url; const Picture: TPicture; var Handled: Boolean)` | 需要一张图片时 |
| `OnScroll` | `TNotifyEvent` | 滚动位置变化 |
| `OnZoomChange` | `TNotifyEvent` | 缩放变化 |
| `OnExtensionError` | `(Sender; const Extension: string; const Error: Exception)` | 扩展渲染出错 |

### 3.10 其它公开方法

```pascal
Viewer.RenderDocument(SomeCanvas);              // 把文档画到任意画布（缩略图/打印/测试）
L := Viewer.ScrollOffsetToSourceLine(Viewer.ScrollOffset);  // 视口顶端的源码行号
Off := Viewer.SourceLineToScrollOffset(10);     // 让第 10 行(从 0 起)滚到顶端所需的偏移
Viewer.DisplayList;                             // 布局结果（只读，供高级用途）
Viewer.LayoutCount;                             // 布局块数量
```

---

## 4. TMarkdownEditor

### 4.1 属性（published）

| 属性 | 类型 | 说明 |
|------|------|------|
| `Text` | `string` | 编辑器内容 |
| `Theme` / `ThemePreset` | 同查看器 | 着色与界面配色 |
| `ContentScale` | `Single` | 同查看器 |
| `ShowLineNumbers` | `Boolean` | 行号栏，默认 True |
| `ReadOnly` | `Boolean` | 只读模式，默认 False |
| `IndentWidth` | `Integer` | Tab 插入的空格数，默认 2 |

### 4.2 方法

```pascal
Editor.LoadFromFile('a.md');
Editor.SaveToFile('a.md');
Editor.InsertText('**加粗**');     // 在光标处插入（替换选区）
Editor.SelectRange(Start, Len);   // 按字符偏移选区
P := Editor.CaretPosition;        // 光标字符偏移
N := Editor.LineCount;            // 源码行数
Editor.HighlightMatches('TODO');  // 标记所有匹配
Editor.ClearHighlights;
Editor.FocusCaret;                // 让控件获得焦点并显示光标
if Editor.Modified then ...;      // 有未保存的修改（撤销栈非空）
L := Editor.ScrollOffsetToSourceLine(...);   // 与查看器同名的行号换算
```

### 4.3 事件

| 事件 | 签名 | 触发时机 |
|------|------|----------|
| `OnChange` | `(const Sender: TObject)` | 文本被修改（输入、删除、粘贴、撤销等） |
| `OnCaretChange` | `TNotifyEvent` | 光标移动 |
| `OnSelectionChange` | `TNotifyEvent` | 选区变化 |

### 4.4 内置按键

| 按键 | 行为 |
|------|------|
| 方向键 / Home / End / PgUp / PgDn | 移动光标（Shift 组合为选区） |
| Ctrl+方向键 / Ctrl+Home / Ctrl+End | 按词 / 文档边界移动 |
| Tab / Shift+Tab | 插入 / 删除 `IndentWidth` 个空格（选区为多行时整块缩进） |
| Enter | 延续上一行的列表标记（`- `、`1. `、`> ` 等）；在空列表项上按 Enter 会删掉标记退出列表 |
| Backspace / Delete | 常规删除（无列表标记特例） |
| Ctrl+Z / Ctrl+Y | 撤销 / 重做 |
| Ctrl+C / Ctrl+X / Ctrl+V | 复制 / 剪切 / 粘贴 |
| Ctrl+A | 全选 |
| 拖拽 | 选择；双击选词 |

### 4.5 折叠

标题与列表项的行号栏左侧有折叠箭头（标题/列表首行），点击可折叠/展开。折叠是**视图层**行为，不改动文本。

---

## 5. 主题与缩放

三个概念不要混淆：

- **`Theme`**：颜色与版式的来源——文字/背景色、六档标题字号、代码块底色、表格线、token 着色等。`ThemePreset` 只是 `Light`/`Dark` 两套内置参数的快捷方式。想自定义时基于预设克隆再改字段：

  ```pascal
  Viewer.ThemePreset := TMarkdownThemePreset.Dark;
  ```

- **`Zoom`**（查看器）：改变文档排版大小。实现方式是**用缩放后的主题重新布局**，不是画布变换，所以放大后字形边缘依然锐利；代价是每次缩放都要重排。
- **`ContentScale`**：给整个主题乘一个系数（字号、间距一起变）。适合窗体整体处理高 DPI 时用。

字体默认值随平台自动选择：Windows `Segoe UI`/`Consolas`，macOS `Helvetica Neue`/`Menlo`，Linux `DejaVu Sans`/`DejaVu Sans Mono`，均可通过 `Theme` 覆盖。

---

## 6. 编译与测试

仓库自带构建脚本（Windows 上开发，路径以本机 Lazarus 为准，见脚本头注释）：

```sh
tools/build/build.sh test_core        # 核心库测试
tools/build/build.sh test_all_layout  # 布局单元全链接检查
tools/build/build_lcl.sh test_lcl     # 绘制后端测试（需要 LCL）
tools/build/build_lcl.sh test_viewer  # 查看器测试，输出 build/viewer-final.png
tools/build/build_lcl.sh test_editor  # 编辑器测试，输出 build/editor.png
```

交叉编译检查（Windows 主机 → Linux，只编译不链接）：

```sh
tools/build/build_linux.sh gtk2 test_viewer   # widgetset 可换 gtk3/qt5（需有对应预编译单元）
```

组件包与演示程序用 `lazbuild`：

```sh
lazbuild packages/markdown4d_lcl.lpk
lazbuild demo/markdown4d_demo.lpi
```

---

## 7. 已知限制

1. **没有 alpha 混合**：LCL 画布无 alpha 通道。选区、搜索标记画在文字**下方**作为底色，文字始终可读；代价是代码块内的选区会被块背景色遮住。
2. **不下载远程图片**：`http(s)://` 的图片显示占位框，需要用 `OnResolveImage` 自行提供。
3. **拖拽生成图像**：控件的 `RenderDocument(ACanvas)` 要求目标画布与控件同尺寸；这是给测试、缩略图、打印用的。
4. **Windows 平台特性**在非 Windows 上按原库设计降级：自动滚动的平移光标、`GetAsyncKeyState` 检测等返回 False/空实现。
5. 编辑器的 `Modified` 基于"撤销栈非空"，保存后如需复位请整体重设 `Text`。

更多移植细节（FPC 限制清单、每个坑的绕法）见 `docs/porting.md`；仓库总览见 `README.md`。
