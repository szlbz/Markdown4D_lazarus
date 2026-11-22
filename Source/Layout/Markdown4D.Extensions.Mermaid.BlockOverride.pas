{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Extensions.Mermaid.BlockOverride;

{$SCOPEDENUMS ON}

interface

uses
  Markdown4D.Ast.Interfaces,
  Markdown4D.Extensions.Interfaces,
  Markdown4D.Layout.Interfaces,
  Markdown4D.Layout.BlockOverride,
  Markdown4D.Extensions.Mermaid,
  Markdown4D.Compat.Str,
  character;

type
  TMermaidBlockOverride = class(TInterfacedObject, ILayoutBlockOverride)
  strict private
    class var FRegistered: Boolean;
    function GetName: string;
    function Handles(const Node: IMarkdownNode): Boolean;
    function LayoutBlock(const Node: IMarkdownNode; const Top: Single; const Context: ILayoutBlockContext): Single;
    class function TryResolveModel(const Node: IMarkdownNode; out Model: IMermaidModel): Boolean;
  public
    const
      OverridePriority = TMarkdownPriorities.ExtensionLayoutOverride;
    class procedure RegisterOverride;
  end;

implementation

uses
  SysUtils,
  Markdown4D.Layout.Engine,
  Markdown4D.Extensions.Mermaid.Layout;

class procedure TMermaidBlockOverride.RegisterOverride;
begin
  if FRegistered then
    Exit;

  TMarkdownLayoutEngine.RegisterBlockOverride(TMermaidBlockOverride.Create, OverridePriority);
  TLayoutDocumentProcessorRegistry.Register(TMermaidExtension.ExtensionName, TMermaidExtension.CreateDocumentProcessor);
  FRegistered := True;
end;

function TMermaidBlockOverride.GetName: string;
begin
  Result := TMermaidExtension.ExtensionName;
end;

class function TMermaidBlockOverride.TryResolveModel(const Node: IMarkdownNode; out Model: IMermaidModel): Boolean;
begin
  Result := TMermaidExtension.TryGetModel(Node, Model);
end;

function TMermaidBlockOverride.Handles(const Node: IMarkdownNode): Boolean;
var
  Model: IMermaidModel;
begin
  
  Result := TryResolveModel(Node, Model);
end;

function TMermaidBlockOverride.LayoutBlock(const Node: IMarkdownNode; const Top: Single;
  const Context: ILayoutBlockContext): Single;
var
  Model: IMermaidModel;
  Height: Single;
  Bounds: TLayoutRectF;
begin
  
  if not TryResolveModel(Node, Model) then
  begin
    Result := 0;
    Exit;
  end;

  Height := TMermaidLayouter.PreferredHeight(Model, Context.Width, Context.Theme, Context.Measurer);
  Bounds := TLayoutRectF.Create(0, Top, Context.Width, Top + Height);
  TMermaidLayouter.Draw(Model, Bounds, Context.Theme, Context.Measurer, Context.Canvas);

  Result := Height;
end;

end.
