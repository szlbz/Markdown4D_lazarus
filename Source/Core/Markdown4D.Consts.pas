{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Consts;

{$SCOPEDENUMS ON}

// Every text the viewer and the editor show to a reader, in one place, so the
// Delphi translation tools find them.

interface

resourcestring
  CopyMenuCaption = 'Copy';
  CopyAsMarkdownMenuCaption = 'Copy as Markdown';
  CutMenuCaption = 'Cut';
  PasteMenuCaption = 'Paste';
  DeleteMenuCaption = 'Delete';
  SelectAllMenuCaption = 'Select All';
  UndoMenuCaption = 'Undo';
  RedoMenuCaption = 'Redo';

  CopyCodeCaption = 'Copy';
  CopiedCodeCaption = 'Copied';

  NoteAlertTitle = 'Note';
  TipAlertTitle = 'Tip';
  ImportantAlertTitle = 'Important';
  WarningAlertTitle = 'Warning';
  CautionAlertTitle = 'Caution';

implementation

end.
