{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Editor.Highlights;

{$SCOPEDENUMS ON}

// Search hits as offset ranges, kept in step with the text and clipped to the
// line a host is about to paint. The ranges are framework-neutral; only turning
// them into rectangles belongs to a concrete editor control.

interface

uses
  Markdown4D.Editor.Model,
  Markdown4D.Compat.Str,
  character;

type
  TEditorHighlightSpan = record
    StartOffset: Integer;
    EndOffset: Integer;
    class function Create(const StartOffset, EndOffset: Integer): TEditorHighlightSpan; static;
    function Length: Integer;
  end;

  TMarkdownEditorHighlights = class
  strict private
    FNeedle: string;
    FOptions: TMarkdownFindOptions;
    FSpans: TArray<TEditorHighlightSpan>;
  public
    procedure SetNeedle(const Model: TMarkdownEditorModel; const Needle: string;
      const Options: TMarkdownFindOptions);
    procedure Clear;
    // Call after the text changed so the ranges follow the new content.
    procedure Refresh(const Model: TMarkdownEditorModel);
    function IsActive: Boolean;
    function Count: Integer;
    function Spans: TArray<TEditorHighlightSpan>;
    // The parts of the ranges that fall inside one visual row, already clipped.
    function SpansWithin(const RangeStart, RangeEnd: Integer): TArray<TEditorHighlightSpan>;
  end;

implementation

uses
  Math,
  Generics.Collections;

class function TEditorHighlightSpan.Create(const StartOffset, EndOffset: Integer): TEditorHighlightSpan;
begin
  Result.StartOffset := StartOffset;
  Result.EndOffset := EndOffset;
end;

function TEditorHighlightSpan.Length: Integer;
begin
  Result := EndOffset - StartOffset;
end;

procedure TMarkdownEditorHighlights.SetNeedle(const Model: TMarkdownEditorModel; const Needle: string;
  const Options: TMarkdownFindOptions);
begin
  FNeedle := Needle;
  FOptions := Options;

  Refresh(Model);
end;

procedure TMarkdownEditorHighlights.Clear;
begin
  FNeedle := '';
  FSpans := [];
end;

procedure TMarkdownEditorHighlights.Refresh(const Model: TMarkdownEditorModel);
var
  NeedleLength: Integer;
  Spans: TList<TEditorHighlightSpan>;
  Start: Integer;
begin
  FSpans := [];

  if (FNeedle = '') or (Model = nil) then
    Exit;

  NeedleLength := Length(FNeedle);

  // A search hit list grows with document size (every occurrence of the
  // needle), so a TList avoids the O(n^2) cost of growing an array one
  // element at a time.
  Spans := TList<TEditorHighlightSpan>.Create;
  try
    for Start in Model.FindAllMatches(FNeedle, FOptions) do
    begin
      Spans.Add(TEditorHighlightSpan.Create(Start, Start + NeedleLength));
    end;

    FSpans := Spans.ToArray;
  finally
    Spans.Free;
  end;
end;

function TMarkdownEditorHighlights.IsActive: Boolean;
begin
  Result := FNeedle <> '';
end;

function TMarkdownEditorHighlights.Count: Integer;
begin
  Result := Length(FSpans);
end;

function TMarkdownEditorHighlights.Spans: TArray<TEditorHighlightSpan>;
begin
  Result := FSpans;
end;

function TMarkdownEditorHighlights.SpansWithin(const RangeStart, RangeEnd: Integer): TArray<TEditorHighlightSpan>;
var
  Span: TEditorHighlightSpan;
  Outside: Boolean;
begin
  Result := [];

  for Span in FSpans do
  begin
    Outside := (Span.EndOffset <= RangeStart) or (Span.StartOffset >= RangeEnd);
    if Outside then
      Continue;

    Result := Result + [TEditorHighlightSpan.Create(Max(Span.StartOffset, RangeStart),
      Min(Span.EndOffset, RangeEnd))];
  end;
end;

end.
