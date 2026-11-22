{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Extensions.Toc;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Ast.Interfaces,
  Markdown4D.Extensions.Interfaces,
  Markdown4D.Compat.Str,
  character;

type
  TMarkdownTocMarkers = class
  public
    const
      ExtensionDataKey = 'markdown4d.toc';
    // The list of links to the headings that stands in for a [[_TOC_]] or
    // [TOC] paragraph. The paragraph itself stays, so the source keeps the
    // marker.
    class function TryGetContents(const Node: IMarkdownNode; out Contents: IMarkdownNode): Boolean; static;
  end;

  // A table of contents: a paragraph that holds nothing but [[_TOC_]] or [TOC]
  // shows a nested list of links to every heading of the document.
  TTocExtension = class(TInterfacedObject, IMarkdownExtension)
  public
    procedure Setup(const Pipeline: IMarkdownPipelineBuilder);
  end;

implementation

uses
  SysUtils,
  Markdown4D.Ast.Builder,
  Markdown4D.Toc;

type
  TTocMarkerProcessor = class(TInterfacedObject, IMarkdownDocumentProcessor)
  private
    const
      // [[_TOC_]] reads as [[ and an emphasised TOC and ]], so its plain text
      // has lost the underscores.
      Markers: array[0..1] of string = ('[TOC]', '[[TOC]]');
      AnchorMark = '#';
    class function IsMarker(const Node: IMarkdownNode): Boolean; static;
    class function TryAppendPlainText(const Node: IMarkdownNode; const Text: TStringBuilder): Boolean; static;
    class function ContentsOf(const Toc: IMarkdownToc): IMarkdownNode; static;
    class procedure AddEntry(const Builder: IMarkdownDocumentBuilder; const Entry: IMarkdownTocEntry); static;

  public
    procedure Process(const Document: IMarkdownDocument);
  end;

class function TMarkdownTocMarkers.TryGetContents(const Node: IMarkdownNode; out Contents: IMarkdownNode): Boolean;
var
  Data: IInterface;
begin
  Contents := nil;

  
  Result := Node.TryGetExtensionData(ExtensionDataKey, Data) and Supports(Data, IMarkdownNode, Contents);
end;

procedure TTocExtension.Setup(const Pipeline: IMarkdownPipelineBuilder);
var
  Processor: IMarkdownDocumentProcessor;
begin
  Processor := TTocMarkerProcessor.Create;
  Pipeline.RegisterDocumentProcessor(Processor, TMarkdownPriorities.ExtensionProcessor);
end;

// GitLab honours the marker only on a line of its own, so only a paragraph of
// the document itself is looked at.
procedure TTocMarkerProcessor.Process(const Document: IMarkdownDocument);
var
  Contents: IMarkdownNode;
  Index: Integer;
  Child: type of (Document.Children[Index]);
  Toc: IMarkdownToc;
begin
  Contents := nil;

  for Index := 0 to Document.ChildCount - 1 do
  begin
    Child := Document.Children[Index];
    if not IsMarker(Child) then
      Continue;

    if Contents = nil then
    begin
      Toc := TMarkdownToc.FromDocument(Document);
      Contents := ContentsOf(Toc);
    end;

    Child.SetExtensionData(TMarkdownTocMarkers.ExtensionDataKey, Contents);
  end;
end;

class function TTocMarkerProcessor.IsMarker(const Node: IMarkdownNode): Boolean;
var
  Text: TStringBuilder;
  PlainText: string;
  Marker: string;
begin
  Result := False;
  if Node.Kind <> TMarkdownNodeKind.Paragraph then
    Exit;

  Text := TStringBuilder.Create;
  try
    if not TryAppendPlainText(Node, Text) then
      Exit;

    PlainText := Text.ToString;
    for Marker in Markers do
    begin
      if PlainText = Marker then
      begin
        Result := True;
        Exit;
      end;
    end;
  finally
    Text.Free;
  end;
end;

// False for anything but text and emphasis, so a link or an image never reads
// as a marker.
class function TTocMarkerProcessor.TryAppendPlainText(const Node: IMarkdownNode; const Text: TStringBuilder): Boolean;
var
  Index: Integer;
  Child: IMarkdownNode;
begin
  Result := True;

  for Index := 0 to Node.ChildCount - 1 do
  begin
    Child := Node.Children[Index];

    case Child.Kind of
      TMarkdownNodeKind.Text:
        Text.Append((Child as IMarkdownText).Literal);
      TMarkdownNodeKind.Emphasis, TMarkdownNodeKind.Strong:
        Result := TryAppendPlainText(Child, Text);
    else
      Result := False;
    end;

    if not Result then
      Exit;
  end;
end;

class function TTocMarkerProcessor.ContentsOf(const Toc: IMarkdownToc): IMarkdownNode;
var
  Builder: IMarkdownDocumentBuilder;
  Entry: IMarkdownTocEntry;
begin
  Builder := TMarkdownDocumentBuilder.Create;
  Builder.BeginBulletList;

  for Entry in Toc do
  begin
    AddEntry(Builder, Entry);
  end;

  Builder.EndList;
  Result := Builder.Build.Children[0];
end;

class procedure TTocMarkerProcessor.AddEntry(const Builder: IMarkdownDocumentBuilder; const Entry: IMarkdownTocEntry);
var
  HasChildren: Boolean;
  Index: Integer;
begin
  Builder.BeginListItem;
  Builder.BeginParagraph;
  Builder.Link(Entry.Caption, AnchorMark + Entry.Anchor);
  Builder.EndParagraph;

  HasChildren := (Entry.ChildCount > 0);
  if HasChildren then
  begin
    Builder.BeginBulletList;
    for Index := 0 to Entry.ChildCount - 1 do
    begin
      AddEntry(Builder, Entry.Children[Index]);
    end;
    Builder.EndList;
  end;

  Builder.EndListItem;
end;

end.
