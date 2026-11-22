# Markdown4D on Lazarus

A Markdown viewer and a Markdown source editor for LCL applications, ported
from the Delphi original. The document is parsed once, laid out once, and then
painted through a small `IPainter` interface, so the same layout serves a
VCL form, an LCL form, or a bitmap.

## What the editor does

- Soft wrapping, with the caret staying on the line it was on
- Syntax colours for headings, emphasis, code, links and fences
- Headings and list items fold from the arrow in the gutter
- Undo, redo, and the usual selection and clipboard keys
- The document on the right follows the source after a short pause

## What the viewer does

- CommonMark 0.31.2 and GFM, 676 of 676 conformance cases
- Tables, task lists, alerts, and `<details>` sections that open and close
- Syntax highlighting in fenced code, driven by the language after the fence
- Math and diagrams when the extensions are registered
- Selection, search with highlights, and a copy button over code blocks
- Zoom with Ctrl and the wheel, from 25% to 500%

> Folding and soft wrapping both live in the model, not in the control, so a
> third widgetset would only have to draw the rows it is given.

```pascal
procedure TMainForm.HandlePreviewTimer(Sender: TObject);
begin
  FPreviewTimer.Enabled := False;
  FViewer.Text := FEditor.Text;
end;
```

| Part | Unit | Lines |
| --- | --- | --- |
| Viewer | `Markdown4D.Lcl.Viewer` | shell over the model |
| Editor | `Markdown4D.Lcl.Editor` | shell over the model |
| Painter | `Markdown4D.Lcl.Painter` | `IPainter` over a canvas |

Open a `.md` file with the button above to try a document of your own.
