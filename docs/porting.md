# Porting notes

What the move from Delphi to Free Pascal actually cost, and how each obstacle
was got around. Everything under `Source/Core`, `Source/Layout` and
`Source/Compat` is produced by `tools/port/regen.sh` from `Source/Orig`; the
notes below are about the machinery in `tools/port/port.py` that gets it there,
and about the hand-written pieces it cannot reach.

## The shape of the port

The Delphi sources are 108 units and about 60,000 lines. They are compiled
here with

```
fpc -Mdelphiunicode -FcUTF8 -O1 -Sh
```

`-Mdelphiunicode` keeps `string` = `UnicodeString` and keeps Delphi's `class`
semantics, which removes most of the source churn. The rest is mechanical and
is done by `port.py`: it parses each unit, rewrites what FPC will not accept,
and writes the result. The script runs in two passes - the first builds an
index of every type, field, property and method in the codebase, the second
rewrites each file with that index in hand.

What the last run reported:

```
files=108  inline var=1034  inline const=2711  for-var=467  needs review=0
```

`needs review` counts the hunks the script could not type on its own; it has
been zero for a while, and `tools/port/overrides.json` (26 entries, each
pinned to `file:line`) is what keeps it there.

## Delphi features FPC does not have

### Inline `var` and `const`

Delphi allows a declaration in the middle of a routine body; FPC does not.

```pascal
const Width = TextWidth(Text, Font);        // Delphi
const Metrics = TextMetricsOf(Font);
```

The declaration is hoisted into the routine's `var` block and the initialiser
turned into an assignment at the point the declaration stood. Two hazards:

- **The declared name may be the same in two sibling blocks with different
  types.** A `case` with a `Builder` per branch is the common case. The script
  renames the second and later ones (`Builder2`, `Builder3`) inside their own
  block, so the meaning stays local.
- **A later declaration may refer to an earlier one.** `const A = F(x); const
  B = A[0] + 1;` needs `A` published to the scope *as it is discovered*, not
  after the whole routine has been scanned. Getting this wrong made `Matches`
  come out as `Boolean` in one file, which then broke three call sites.

### `for var` loops

`for var Index := 0 to Count - 1 do` becomes a hoisted loop variable. Where the
loop variable shadows an outer name the hoisted one is renamed, because the
outer one is still in scope.

### Nested generics

`TDictionary<string, TList<IMarkdownNode>>` crashes the FPC 3.3.1 compiler in
the parser, with an internal error rather than a message. The script generates
an alias unit-level type - `TM4DGen1`, `TM4DGen2`, ... - and names it in place
of the nested form.

### Class helpers

`TArray.Sort<T>(A)` is a Delphi class helper on `TArray`. FPC has
`TArrayHelper<T>`, so the call is rewritten:

```pascal
TArray.Sort<TMermaidBaryKey>(Keys)      // Delphi
TArrayHelper<TMermaidBaryKey>.Sort(Keys) // FPC
```

`ensure_generics_uses()` adds `Generics.Collections` to the interface `uses`
clause whenever a generic container appears in a field, parameter or result
type, because FPC wants the unit in scope wherever the type is spelled, not
only where it is used.

### Nested types referenced across units

A private nested type - `TThemeData.TAlertColorArray` - is invisible outside
its unit. FPC is stricter than Delphi about this and refuses the reference
rather than resolving it through the class. `expand_nested_type()` writes the
definition out at the point of use, and `nested_alias_plan()` adds a unit-level
alias when the nested type is the parameter of a virtual method, where the
definition cannot be repeated.

### Generic delegates

`TFunc<T, TResult>`, `TProc`, `TProc<T>` live in `System.SysUtils` in Delphi
and nowhere in FPC. They are declared by hand in
`Source/Compat/Markdown4D.Compat.Str.pas`:

```pascal
{$modeswitch functionreferences}{$modeswitch anonymousfunctions}
type
  TFunc<T, TResult> = reference to function(Arg1: T): TResult;
  TProc = reference to procedure;
```

## Units that had to be written

Delphi 10+ RTL units with no FPC counterpart, each replaced by a small unit of
the same name under `Source/Compat`:

| Delphi unit | What the port needs from it | How it is provided |
| --- | --- | --- |
| `System.Hash` | `THashBobJenkins.GetHashValue` | three overloads over FPC's `BobJenkinsHash` |
| `System.NetEncoding` | base64, URL decode | hand-written `M4DBase64Decode`, `M4DUrlDecode` |
| `System.Threading` | `TTask.Run`, `TThread.Queue(nil, anon)` | a thread per task, a queue of self-freeing closures |
| `System.IOUtils` | `TPath.Combine`, `TFile.ReadAllBytes` | direct calls to `SysUtils` |
| `System.Net.HttpClient` | `THTTPClient`, `IHTTPResponse` | `fphttpclient` + `opensslsockets` |
| `System.Net.URLClient` | `TURLClient` | empty unit, for the `uses` clause only |
| `System.JSON` | `TJSONObject` and friends | `fpjson` wrapped |
| `System.RegularExpressions` | `TRegEx` | `RegExpr` wrapped |
| `System.UITypes` | `TFontStyle`, `TFontStyles`, `TAlphaColor` | declared with `{$SCOPEDENUMS ON}` |

`Markdown4D.Compat.Str` also carries what `System.SysUtils` gives Delphi and
FPC spells differently: `Trim`, `TStringBuilder`, `TStopwatch`, `TStringHelper`
and the generic delegates above.

## Type inference for the hoisted declarations

Hoisting an inline declaration needs a type for it, and the type is usually
nowhere in writing. `expr_type()` infers it from the expression, which turns
out to be the most delicate part of the whole port. The cases that mattered:

- `FTheme.AlertColors[Kind]` - a *field* of the same name inside a nested
  record was shadowing the *property* that callers actually see. Properties are
  now collected before fields when a class body is indexed.
- `Offset * BytesPerPixel` - `Offset` resolved to a class *method* because the
  local name was looked up after the class members. Locals are now searched in
  two passes, before anything else.
- `FLine[FPosition]` - the field `FLine` is not the type `TMermaidMessageLine`;
  an unrelated function of the same name was winning the lookup. Member types
  are now resolved along the inheritance chain (`TypeIndex.member_type`).
- `High(Result)`, `High(SomeEnum)` - must give `Integer` and the enum type,
  not the type of `Result`.
- `ScannerClass.Create(...)` - `class of` needs `strip_class_of` around
  `resolve(...)`, or the result is the metaclass.
- String concatenation wins over the operand types: `'a' + B` is a `string`
  even when `B` is a `Char`.
- A call to a procedural variable (`FMeasure(...)`) has the variable's return
  type, which lives in a separate `proc_returns` table.

Two structural bugs in the scanner are worth recording because they were
silent: `find_routines()` appended a routine twice when an `end` closed a
record inside a routine body, and it popped a pending routine on that same
`end`.

## What was hand-written

`Source/Lcl` is new code, not converted code:

- **`Markdown4D.Lcl.Painter`** - `IPainter` over a `TCanvas`. The VCL version
  drew text with DirectWrite and wedges through a GDI alpha blend; here text
  goes through `TextOut` and shapes through `Canvas.Polygon`. Fonts are cached
  per style *and* per scale, because the editor and the viewer measure at
  scale 1 and draw at the control's scale. Text metrics come from
  `GetTextMetrics` on the offscreen canvas, and `Baseline` is `tmAscent`, which
  is what the layout engine expects.
- **`Markdown4D.Lcl.Viewer`** - the shell around `Markdown4D.Viewer.Model`.
  Zoom is *not* a transform here: the model lays the document out again with a
  scaled theme, so the painter always works at scale 1 and only shifts the
  origin to scroll. That keeps glyph positions exact and costs a relayout per
  zoom step, which is what the VCL control did too.
- **`Markdown4D.Lcl.Editor`** - the shell around `Markdown4D.Editor.Model`,
  `.Rows`, `.Highlighter` and `.Keys`. FPC's `{$SCOPEDENUMS ON}` means the
  token kinds are spelled `TMarkdownSourceTokenKind.HeadingMarker` throughout.
- **`Markdown4D.Lcl.Images`** - bytes to a `TGraphic`. SVG goes through
  `TMarkdownSvgSupport`, and any alpha channel is flattened onto the page
  colour, because a `TCanvas` composites nothing.

## Traps in the LCL that cost time

- `TCanvas.ClipRect` is honoured **only** while `TCanvas.Clipping` is `True`,
  and assigning it *replaces* the clip region rather than narrowing it. The
  painter keeps its own stack and intersects before assigning.
- `TWinControl.SetFocus` on a form that is not showing raises
  `EInvalidOperation` instead of doing nothing, so the viewer checks
  `Form.Showing` first.
- `TControl.PaintTo` does nothing until the control has a window handle, which
  a form that is never shown never gives it. The controls therefore expose
  `RenderDocument(ACanvas)`, which paints onto any canvas of the control's
  size - used by the tests, and useful for thumbnails and printing.
- An interface field is a *reference*: assigning a second `IPainter` to the
  field the measuring painter is held by drops the last reference and frees it.
  The editor learned this the hard way (an access violation inside
  `MeasureText`); the measuring painter now has a field of its own.
- `fpc.exe` silently ignores a `-Fu` whose path is spelled `D:/...`; it wants
  `D:\...`. `tools/build/build_lcl.sh` says so at the top.

## Linux (GTK2/3, QT5/6)

The controls use only the widgetset-neutral part of the LCL - `TCanvas`,
`TFont`, `LCLIntf` - and every Windows-only unit that the port inherited is
guarded: `Image.Glyphs.Gdi`, `AutoScroll.Cursors` and `Layout.Pointer` compile
to empty implementations off `MSWINDOWS`, exactly as in the original library.
`GetTextMetrics`, the one WinAPI-shaped call the painter makes, is implemented
by all four widgetsets (checked in `gtk2winapi.inc`, `gtk3winapi.inc`,
`qtwinapi.inc`).

`tools/build/build_linux.sh` cross-compiles the three LCL tests from a Windows
host to x86_64-linux against the prebuilt LCL units and stops before linking
(`-s`), which still type-checks every unit against the real widgetset ppus:

```
tools/build/build_linux.sh gtk2 test_lcl
tools/build/build_linux.sh gtk2 test_viewer
tools/build/build_linux.sh gtk2 test_editor
```

All three pass against **GTK2**. This checkout ships no prebuilt GTK3/QT5 LCL
units (`lcl/units/x86_64-linux/{gtk3,qt5}` hold only a marker), so those two
could not be type-checked here; the widgetset difference lives inside the LCL,
not in this library, and the QT6 interface exists in the tree but was likewise
not prebuilt. Run `lazbuild` on a Linux box to build and then run the same
three tests there.

Two portability fixes that the cross-compile surfaced:

- `Compat.IOUtils` used `Path[1] in [PathDelim, DriveDelim]`; a `WideChar`
  subscript is not an ordinal to the compiler when one of the set elements is
  a typed constant, so the two probes are spelled out as comparisons.
- The theme hardcoded `Segoe UI` and `Consolas`. The defaults are now picked
  per platform: `Segoe UI`/`Consolas` on Windows, `Helvetica Neue`/`Menlo` on
  macOS, `DejaVu Sans`/`DejaVu Sans Mono` elsewhere - the last pair ships with
  essentially every Linux distribution, and fontconfig substitutes when it is
  missing.

What differs at runtime on Linux, none of it through this library's own code:
text renders through FreeType rather than DirectWrite, so glyph metrics move a
little and the layout engine adapts because everything is measured, never
hardcoded; the bundled math font (`Markdown4D.Math.Font`) falls back to the
platform name when no installer runs; and the platform cursor/pointer helpers
(`IsPrimaryButtonDown`, autoscroll pan cursors) report `False`, so those two
features degrade the way the original library always did off Windows.
