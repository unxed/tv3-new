{ Two small one-row views that show a value of the system: a clock (TClockView) and the memory in use by the
  program (THeapView). The program calls Update of each view from its idle handler or a timer; a view repaints
  only when its text has changed. Both draw one row of text on a background of blanks, in the colour of
  palette entry 1 of the view. The views are used by the thread of the user interface only. }
unit TvGadgets;

{$mode objfpc}
{$H+}

interface

uses
  SysUtils, TvGeom, TvColors, TvEvents, TvDrawBuf, TvViews;

type
  TClockView = class;

  TClockFormat = function(H, M, S: Word; Seconds, Separator, Hour12: Boolean): AnsiString;
  TClockClick = procedure(Sender: TClockView; var Event: TEvent) of object;
  TClockNowFunc = function: TDateTime;
  THeapValueFunc = function: Int64;

  TClockView = class(TView)
  private
    OwnPalette: TPalette;
    OwnPaletteSource: ShortString;
  public
    ShowSeconds: Boolean;
    BlinkSeparator: Boolean;
    Hour12: Boolean;
    AutoSize: Boolean;
    RightAlign: Boolean;
    Margin: Integer;
    FormatHook: TClockFormat;
    OnClick: TClockClick;
    PaletteStr: ShortString;
    TimeStr: AnsiString;
    constructor Create(const Bounds: TRect);
    destructor Destroy; override;
    function GetPalette: TPalette; override;
    function ClockText: AnsiString; virtual;
    { The program calls it; TView has no such method, so it is introduced here. }
    procedure Update; virtual;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    function MsToNextChange: Integer;
    procedure FitWidth(W: Integer);
  end;

  THeapView = class(TView)
  private
    OwnPalette: TPalette;
    OwnPaletteSource: ShortString;
  public
    Kb: Boolean;
    ValueHook: THeapValueFunc;
    PaletteStr: ShortString;
    HeapStr: AnsiString;
    constructor Create(const Bounds: TRect);
    constructor CreateKb(const Bounds: TRect);
    destructor Destroy; override;
    function GetPalette: TPalette; override;
    function HeapText: AnsiString; virtual;
    procedure Update; virtual;
    procedure Draw; override;
  end;

function ClockFormatDefault(H, M, S: Word; Seconds, Separator, Hour12: Boolean): AnsiString;
function HeapInUse: Int64;

var
  ClockNow: TClockNowFunc = nil;
  GadgetPalette: ShortString = #2;

implementation

end.
