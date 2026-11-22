{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Layout.HitTest;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Ast.Interfaces,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Layout.DisplayList,
  Markdown4D.Compat.Str,
  character;

type
  TMarkdownTextHit = record
    Run: IDisplayTextRun;
    CharacterIndex: Integer;
  end;

  TMarkdownHitTester = class
  private
    class function NextIndex(const DisplayList: IMarkdownDisplayList; const Index: Integer;
      const Point: TLayoutPointF): Integer;
    class function NearestCharacterIndex(const Run: IDisplayTextRun; const Point: TLayoutPointF;
      const Measurer: ITextMeasurer): Integer;

  public
    class function TryFindLink(const DisplayList: IMarkdownDisplayList; const Point: TLayoutPointF;
      out Link: IMarkdownLink): Boolean;
    class function TryFindDisclosure(const DisplayList: IMarkdownDisplayList; const Point: TLayoutPointF;
      out Disclosure: IDisplayDisclosure): Boolean;
    class function TryFindTextPosition(const DisplayList: IMarkdownDisplayList; const Point: TLayoutPointF;
      const Measurer: ITextMeasurer; out Hit: TMarkdownTextHit): Boolean;
  end;

implementation

uses
  SysUtils;

class function TMarkdownHitTester.TryFindLink(const DisplayList: IMarkdownDisplayList; const Point: TLayoutPointF;
  out Link: IMarkdownLink): Boolean;
var
  Index: Integer;
  Item: IDisplayItem;
  Node: IMarkdownNode;
  IsHit: Boolean;
  IsLinkNode: Boolean;
  FoundLink: Boolean;
begin
  Link := nil;

  Index := 0;
  while Index < DisplayList.ItemCount do
  begin
    Item := DisplayList.Items[Index];
    Node := Item.Node;
    IsHit := Item.Bounds.Contains(Point) and (Node <> nil);
    Index := NextIndex(DisplayList, Index, Point);
    if not IsHit then
      Continue;

    IsLinkNode := (Node.Kind = TMarkdownNodeKind.Link) or (Node.Kind = TMarkdownNodeKind.Autolink);
    FoundLink := IsLinkNode and Supports(Node, IMarkdownLink, Link);
    if FoundLink then
    begin
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

class function TMarkdownHitTester.TryFindDisclosure(const DisplayList: IMarkdownDisplayList;
  const Point: TLayoutPointF; out Disclosure: IDisplayDisclosure): Boolean;
var
  Index: Integer;
  Item: IDisplayItem;
  IsDisclosureHit: Boolean;
begin
  Disclosure := nil;

  for Index := 0 to DisplayList.ItemCount - 1 do
  begin
    Item := DisplayList.Items[Index];
    IsDisclosureHit := (Item.Kind = TDisplayItemKind.Disclosure) and Item.Bounds.Contains(Point) and
      Supports(Item, IDisplayDisclosure, Disclosure);
    if IsDisclosureHit then
    begin
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

class function TMarkdownHitTester.TryFindTextPosition(const DisplayList: IMarkdownDisplayList;
  const Point: TLayoutPointF; const Measurer: ITextMeasurer; out Hit: TMarkdownTextHit): Boolean;
var
  Index: Integer;
  Run: IDisplayTextRun;
  IsTextRunHit: Boolean;
begin
  Hit := Default(TMarkdownTextHit);

  Index := 0;
  while Index < DisplayList.ItemCount do
  begin
    
    IsTextRunHit := Supports(DisplayList.Items[Index], IDisplayTextRun, Run) and
      (Run.Role <> TDisplayTextRunRole.Drawing) and Run.Bounds.Contains(Point);
    Index := NextIndex(DisplayList, Index, Point);
    if not IsTextRunHit then
      Continue;

    Hit.Run := Run;
    Hit.CharacterIndex := NearestCharacterIndex(Run, Point, Measurer);
    Result := True;
    Exit;
  end;

  Result := False;
end;

// The index to test after Index. The content of a scroller is drawn only
// inside its band, so with the point outside the band all of it is passed
// over: a link scrolled out of view does not answer the pointer.
class function TMarkdownHitTester.NextIndex(const DisplayList: IMarkdownDisplayList; const Index: Integer;
  const Point: TLayoutPointF): Integer;
var
  Scroller: IDisplayScroller;
  IsOutsideScroller: Boolean;
begin
  Result := Index + 1;

  
  IsOutsideScroller := Supports(DisplayList.Items[Index], IDisplayScroller, Scroller) and
    not Scroller.Bounds.Contains(Point);
  if IsOutsideScroller then
    Result := Result + Scroller.ItemCount;
end;

class function TMarkdownHitTester.NearestCharacterIndex(const Run: IDisplayTextRun; const Point: TLayoutPointF;
  const Measurer: ITextMeasurer): Integer;
var
  LocalX: Double;
  BestDistance: Double;
  CharCount: Integer;
  Prefix: string;
  PrefixSize: TLayoutSizeF;
  BoundaryX: Single;
  Distance: Double;
begin
  LocalX := Point.X - Run.Bounds.Left;

  Result := 0;
  BestDistance := Abs(LocalX);

  for CharCount := 1 to Length(Run.Text) do
  begin
    Prefix := Copy(Run.Text, 1, CharCount);
    PrefixSize := Measurer.MeasureText(Prefix, Run.Font);
    BoundaryX := PrefixSize.Width;
    Distance := Abs(LocalX - BoundaryX);

    if Distance < BestDistance then
    begin
      BestDistance := Distance;
      Result := CharCount;
    end;
  end;
end;

end.
