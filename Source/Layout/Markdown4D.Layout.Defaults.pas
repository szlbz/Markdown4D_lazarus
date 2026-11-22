{$mode delphiunicode}{$modeswitch typeinquiry}
{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}{$modeswitch implicitfunctionspecialization}
{$WARN 5024 off}{$WARN 5090 off}{$WARN 5091 off}{$WARN 5057 off}
unit Markdown4D.Layout.Defaults;

{$SCOPEDENUMS ON}

interface

const
  // Shared viewer/editor defaults, framework-neutral: the VCL and FMX
  // implementations must stay in lockstep on these values.
  ReferencePixelsPerInch = 96;
  WheelLinesPerNotch = 3;
  MouseWheelDeltaPerNotch = 120;
  ScrollLineDips = 40;
  TextLeftPaddingDips = 6;
  GutterPaddingDips = 8;
  CaretWidthDips = 1;
  FlushTimerIntervalMilliseconds = 25;
  AutoScrollIntervalMilliseconds = 50;
  PreviewDebounceIntervalMilliseconds = 60;

  // Font family mapping shared by the VCL and FMX painters
  MonospaceFamilyName = 'monospace';
  SansSerifFamilyName = 'sans-serif';
  SerifFamilyName = 'serif';
  MathFamilyName = 'math';
  MonospaceFallbackFamilyName = 'Consolas';
  SerifFallbackFamilyName = 'Georgia';
  DefaultFallbackFamilyName = 'Segoe UI';

  ColorChannelMax = 255;

  UnbalancedRestoreMessage = 'RestoreState called without a matching SaveState';

implementation

end.
