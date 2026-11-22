{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit markdown4d_lcl;

{$warn 5023 off : no warning about unused units}
interface

uses
  Markdown4D.Compat.Hash, Markdown4D.Compat.Http, Markdown4D.Compat.IOUtils, 
  Markdown4D.Compat.Json, Markdown4D.Compat.NetEncoding, 
  Markdown4D.Compat.RegEx, Markdown4D.Compat.Str, Markdown4D.Compat.Threading, 
  Markdown4D.Compat.UITypes, Markdown4D.Compat.Url, Markdown4D.Ast.Builder, 
  Markdown4D.Ast.Interfaces, Markdown4D.Ast, Markdown4D.Color.Names, 
  Markdown4D.Consts, Markdown4D.Defines, Markdown4D.Extensions.Alerts, 
  Markdown4D.Extensions.Chart, Markdown4D.Extensions.Gfm, 
  Markdown4D.Extensions.Interfaces, Markdown4D.Extensions.Math, 
  Markdown4D.Extensions.Mermaid, Markdown4D.Extensions.Sample, 
  Markdown4D.Extensions.Toc, Markdown4D.Highlighter.Diff, 
  Markdown4D.Highlighter.Interfaces, Markdown4D.Highlighter.Json, 
  Markdown4D.Highlighter.LineScanner, Markdown4D.Highlighter.Pascal, 
  Markdown4D.Highlighter.Sql, Markdown4D.Highlighter.TokenBuilder, 
  Markdown4D.Highlighter.Xml, Markdown4D.Html.Entities, 
  Markdown4D.Html.Subset, Markdown4D.Math.Chemistry, Markdown4D.Math.Syntax, 
  Markdown4D.Parser.Blocks, Markdown4D.Parser.HtmlBlocks, 
  Markdown4D.Parser.Incremental, Markdown4D.Parser.Inlines, 
  Markdown4D.Parser.Interfaces, Markdown4D.Parser.LineReader, 
  Markdown4D.Parser.LineScanner, Markdown4D.Parser.LinkSyntax, 
  Markdown4D.Parser.References, Markdown4D.Parser.SourceMap, 
  Markdown4D.Parser.StagingBlock, Markdown4D.Pipeline.Configuration, 
  Markdown4D.Pipeline, Markdown4D.Renderer.Html, Markdown4D.Text.FileFormat, 
  Markdown4D.Text.Unescape, Markdown4D.Text.UrlSafety, Markdown4D.Toc, 
  Markdown4D.Version, Markdown4D.Writer.Emphasis, Markdown4D.Writer.Markdown, 
  Markdown4D, Markdown4D.AutoScroll.Cursors, Markdown4D.AutoScroll.Icon, 
  Markdown4D.AutoScroll, Markdown4D.DesignSample, Markdown4D.Editor.Actions, 
  Markdown4D.Editor.ContextMenu, Markdown4D.Editor.Folding, 
  Markdown4D.Editor.Highlighter, Markdown4D.Editor.Highlights, 
  Markdown4D.Editor.InlineStyle, Markdown4D.Editor.Keys, 
  Markdown4D.Editor.Model, Markdown4D.Editor.PreviewPacer, 
  Markdown4D.Editor.PreviewScroll, Markdown4D.Editor.Rows, 
  Markdown4D.Extensions.Chart.BlockOverride, 
  Markdown4D.Extensions.Chart.Layout, 
  Markdown4D.Extensions.Mermaid.BlockOverride, 
  Markdown4D.Extensions.Mermaid.Layout, Markdown4D.Image.Decoder, 
  Markdown4D.Image.Filters, Markdown4D.Image.Glyphs.Gdi, 
  Markdown4D.Image.Glyphs, Markdown4D.Image.Rasterizer, 
  Markdown4D.Image.Svg.Native, Markdown4D.Image.Svg.Path, 
  Markdown4D.Image.Svg.Xml, Markdown4D.Image.Svg, 
  Markdown4D.Layout.AlertIcons, Markdown4D.Layout.BlockOverride, 
  Markdown4D.Layout.Defaults, Markdown4D.Layout.Disclosure, 
  Markdown4D.Layout.DisplayList, Markdown4D.Layout.Engine, 
  Markdown4D.Layout.ExtensionCanvas, Markdown4D.Layout.HitTest, 
  Markdown4D.Layout.InlineHtml, Markdown4D.Layout.Interfaces, 
  Markdown4D.Layout.MeasureCache, Markdown4D.Layout.Pointer, 
  Markdown4D.Layout.Primitives, Markdown4D.Layout.Renderer, 
  Markdown4D.Layout.ResizePacer, Markdown4D.Layout.SelectedMarkdown, 
  Markdown4D.Layout.SourceLineMap, Markdown4D.Layout.SourceMapping, 
  Markdown4D.Layout.TextAnchor, Markdown4D.Layout.TextSearch, 
  Markdown4D.Layout.Zoom, Markdown4D.Math.Font, Markdown4D.Math.Layout, 
  Markdown4D.Theme, Markdown4D.Viewer.Clicks, Markdown4D.Viewer.ContextMenu, 
  Markdown4D.Viewer.ImageDownloader, Markdown4D.Viewer.ImageSettings, 
  Markdown4D.Viewer.Lifetime, Markdown4D.Viewer.Model, 
  Markdown4D.Viewer.ScrollBar, Markdown4D.Viewer.Shared, 
  Markdown4D.Lcl.Editor, Markdown4D.Lcl.Images, Markdown4D.Lcl.Painter, 
  Markdown4D.Lcl.Register, Markdown4D.Lcl.Viewer, LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('markdown4d_lcl', @Register);
end.
