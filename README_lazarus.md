# Markdown4D for Lazarus

A Markdown **viewer** and Markdown **source editor** for Lazarus and Free
Pascal, ported from the Delphi library [Markdown4D](../Markdown4D). The
document model, the parser, the layout engine and the editor logic are shared
with the original; what is new here is the Free Pascal compatibility layer and
two LCL controls that draw them.

![the two controls](build/viewer-final.png)

```pascal
uses Markdown4D.Lcl.Viewer, Markdown4D.Lcl.Editor;

Viewer := TMarkdownViewer.Create(Self);
Viewer.Parent := Self;
Viewer.Align := alClient;
Viewer.Text := '# Hello' + LineEnding + LineEnding + 'Rendered by **LCL**.';

Editor := TMarkdownEditor.Create(Self);
Editor.Parent := Self;
Editor.Align := alClient;
Editor.Text := Viewer.Text;
```

## What you get

| Control | Unit | What it does |
| --- | --- | --- |
| `TMarkdownViewer` | `Markdown4D.Lcl.Viewer` | Renders a document: CommonMark 0.31.2 and GFM, tables, alerts, `<details>`, syntax-highlighted code, math and diagrams through the extensions, selection, search with highlights, links, zoom. |
| `TMarkdownEditor` | `Markdown4D.Lcl.Editor` | Edits Markdown source: soft wrapping, syntax colours, folding, undo and redo, the usual keys, line numbers. |
| `TMarkdownLclPainter` | `Markdown4D.Lcl.Painter` | The `IPainter` the layout engine draws through, over a `TCanvas`. |

Registering `Markdown4D.Lcl.Register` adds both controls to the palette page
**Markdown4D**.

## Getting it into a project

Two ways, both need nothing installed system-wide:

1. **Search paths.** Add these to the project's *Other unit files*
   (`-Fu`) and put the units on the uses clause:

   ```
   Source/Compat  Source/Core  Source/Layout  Source/Lcl
   ```

2. **Package.** Open `packages/markdown4d_lcl.lpk` in Lazarus and press
   *Install*. The controls appear on the palette and the compiler paths are set
   up for you. From a terminal:

   ```
   lazbuild --widgetset=win32 packages/markdown4d_lcl.lpk
   ```

Two demos ship in `demo/`:

- `markdown4d_demo.lpi` - editor and viewer side by side, wired through
  `AttachPreview` for a live preview.
- `markdown4d_view_demo.lpi` - the viewer alone: a markdown file list and a
  heading outline on the left (click either), the document on the right, plus
  the built-in right-click menu, autoscroll and a find box. Window bounds,
  pane sizes, zoom, theme and the last directory/file persist in an ini file
  beside the executable.

```
lazbuild --widgetset=win32 demo/markdown4d_demo.lpi
lazbuild --widgetset=win32 demo/markdown4d_view_demo.lpi
```

## Using the viewer

```pascal
Viewer.Text := Markdown;            // lays the document out again
Viewer.Zoom := 150;                 // percent, 25..500
Viewer.ScrollOffset := 400;         // top of the view, in document pixels
Viewer.ScrollToAnchor('#install');  // bring a heading to the top
Viewer.FindText('layout');          // select the next match and scroll to it
Viewer.HighlightMatches('layout');  // mark every match
Viewer.ThemePreset := TMarkdownThemePreset.Dark;
Viewer.Theme := MyOwnTheme;         // a TMarkdownTheme, kept by the caller
```

Events: `OnLinkClick`, `OnLinkHover`, `OnResolveImage` (supply a `TPicture`
yourself), `OnScroll`, `OnZoomChange`, `OnAutoScrollChange`,
`OnExtensionError`.

Keys: arrows, Page Up/Down, Home/End scroll; Ctrl+A, Ctrl+C (Shift adds the
markdown source, see `CopyAsMarkdown`); Ctrl+plus, minus and 0 zoom. The wheel
scrolls, Ctrl+wheel zooms, Shift+wheel scrolls a wide formula sideways.

A right click opens a built-in menu (copy, copy as markdown, select all) when
the host assigns no `PopupMenu`. A middle click starts autoscroll: the view
pans with the pointer until the next click, key or wheel turn; turn it off
with `AutoScroll := False`. The find and highlight methods all take a
`TMarkdownFindOptions` overload for case and whole-word matching.

Images: a relative source resolves against `DocumentFolder`, which
`LoadFromFile` sets for you. SVG goes through the library's rasteriser; PNG,
JPEG and the rest through `TPicture`. Remote URLs are left as placeholders -
supply them from `OnResolveImage` if the application wants them.

## Using the editor

```pascal
Editor.Text := Source;
Editor.ShowLineNumbers := True;
Editor.IndentWidth := 2;
Editor.ReadOnly := False;
Editor.OnChange := HandleChange;      // the text changed
Editor.OnCaretChange := HandleCaret;  // the caret moved
Editor.SelectRange(10, 5);
Editor.HighlightMatches('TODO');
```

The editor exposes `Undo`/`Redo`/`CanUndo`/`CanRedo`, clipboard methods,
`ZoomIn`/`ZoomOut`/`ResetZoom` with `OnZoomChange`, `OnScroll`,
`FirstVisibleSourceLine`/`ScrollToSourceLine`, and the built-in right-click
menu (undo, redo, cut, copy, paste, delete, select all).

Live preview: `Editor.AttachPreview(Viewer)` keeps a viewer beside the editor
in step - the editor drives, the panes scroll two ways while `SyncScroll` is
on, and `TryAdoptPreviewSelection` moves the reader's selection in the preview
onto the same characters in the source.

`Ctrl+Z`/`Ctrl+Y` undo and redo, `Ctrl+A`/`C`/`X`/`V` select, copy, cut and
paste, `Tab`/`Shift+Tab` indent and outdent, and the arrow keys move by
character, word and document. Clicking the arrow in the gutter folds a heading
or a list item.

## Testing

The port is checked at three levels; all of it runs from a shell, without an
IDE.

```
# the parser and the HTML renderer against the published spec suites
python tools/build/run_specs.py

# the layout engine: every one of the sixty units links and runs
sh tools/build/build.sh test_all_layout && build/test_all_layout.exe

# the LCL layer
sh tools/build/build_lcl.sh test_lcl      && build/test_lcl.exe
sh tools/build/build_lcl.sh test_viewer   && build/test_viewer.exe
sh tools/build/build_lcl.sh test_editor   && build/test_editor.exe
```

The spec suites are CommonMark 0.31.2 (652 examples) and GFM 0.29 (24), all
676 passing. The two LCL tests also write `build/viewer-*.png` and
`build/editor.png`, so a change in the drawing can be looked at.

## Layout of the tree

```
Source/Orig      the Delphi sources, untouched
Source/Compat    units that stand in for the Delphi RTL names FPC lacks
Source/Core      the parser, the AST, the HTML renderer, the highlighters
Source/Layout    the theme, the layout engine, the display list, the models
Source/Lcl       the two controls and the painter (new code)
Source/VclRef    the original VCL controls, kept for reference
packages/        markdown4d_lcl.lpk
demo/            a live preview application and a viewer-only reader
specs/           the CommonMark and GFM conformance suites
tools/port       the mechanical port and its overrides
tools/build      the test programs and the scripts that build them
```

`Source/Core`, `Source/Layout` and `Source/Compat` are **generated** from
`Source/Orig` by `tools/port/regen.sh`; edit the Delphi sources and regenerate
rather than editing the output. `Source/Lcl` is hand-written and is not
regenerated.

## Known limitations

- **No alpha blending.** An LCL canvas has no alpha channel, so a translucent
  colour - the selection, a search mark - is drawn *under* the text as a tint
  rather than blended over it. The text stays readable, which is the part that
  matters; a selection inside a code block is hidden by the block's own
  background.
- **No remote images.** There is no downloader in the LCL build; use
  `OnResolveImage`.
- **VCL only.** The original also had an FMX viewer and editor. Only the VCL
  side was ported, as asked.
- **Text rendering is GDI-class.** The VCL original could draw text through
  DirectWrite. Here everything goes through `TCanvas`, so glyph quality is
  whatever the widgetset gives.

`docs/porting.md` records what FPC made difficult and how each case was
handled. A Chinese usage guide for the two controls lives in
`docs/usage-cn.md`.
