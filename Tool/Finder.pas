unit Finder;

{ The drag-and-drop window finder (like Spy++'s finder tool) and the red
  frame that highlights the window or control under the cursor. Everything
  here works in physical screen coordinates (VclSpy is Per-Monitor V2 aware). }

interface

uses
  Winapi.Windows, Winapi.Messages, System.Classes, System.Types, Vcl.Controls, Vcl.Graphics,
  Vcl.Forms;

type
  TPickEvent = procedure(Sender: TObject; Wnd: HWND; const ScreenPt: TPoint) of object;

  // Press on it, drag over the target, release to pick.
  TFinderTool = class(TCustomControl)
  private
    FDragging: Boolean;
    FLastWnd: HWND;
    FOnPickMove: TPickEvent;
    FOnPickDone: TPickEvent;
    FOnPickCancel: TNotifyEvent;
    procedure StopDragging;
    procedure WMLButtonDown(var Message: TWMLButtonDown); message WM_LBUTTONDOWN;
    procedure WMMouseMove(var Message: TWMMouseMove); message WM_MOUSEMOVE;
    procedure WMLButtonUp(var Message: TWMLButtonUp); message WM_LBUTTONUP;
    procedure WMRButtonDown(var Message: TWMRButtonDown); message WM_RBUTTONDOWN;
    procedure WMCaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property IsDragging: Boolean read FDragging;
    property OnPickMove: TPickEvent read FOnPickMove write FOnPickMove;
    property OnPickDone: TPickEvent read FOnPickDone write FOnPickDone;
    property OnPickCancel: TNotifyEvent read FOnPickCancel write FOnPickCancel;
  end;

  // Hollow, click-through, topmost red frame.
  THighlightFrame = class(TForm)
  private
    FSize: TSize;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMDpiChanged(var Message: TMessage); message WM_DPICHANGED;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowAt(const R: TRect);
    procedure HideFrame;
  end;

// Deepest visible child window at a screen point, including disabled ones
// (WindowFromPoint skips those). Returns 0 for windows of this process.
function WindowAtPoint(const Pt: TPoint): HWND;

implementation

uses
  System.Math;

const
  FrameWidth = 3;

function WindowAtPoint(const Pt: TPoint): HWND;
var
  Child: HWND;
  ClientPt: TPoint;
  Pid: DWORD;
begin
  Result := WindowFromPoint(Pt);
  if Result = 0 then
    Exit;
  Result := GetAncestor(Result, GA_ROOT);
  repeat
    ClientPt := Pt;
    ScreenToClient(Result, ClientPt);
    Child := ChildWindowFromPointEx(Result, ClientPt, CWP_SKIPINVISIBLE or CWP_SKIPTRANSPARENT);
    if (Child = 0) or (Child = Result) then
      Break;
    Result := Child;
  until False;
  GetWindowThreadProcessId(Result, Pid);
  if Pid = GetCurrentProcessId then
    Result := 0;
end;

{ TFinderTool }

constructor TFinderTool.Create(AOwner: TComponent);
begin
  inherited;
  Width := 36;
  Height := 36;
  Cursor := crCross;
  DoubleBuffered := True;
end;

procedure TFinderTool.Paint;
var
  R: TRect;
  C: TPoint;
  Radius: Integer;
begin
  R := ClientRect;
  Canvas.Brush.Color := clWindow;
  Canvas.FillRect(R);
  C := CenterPoint(R);
  Radius := (Min(R.Width, R.Height) div 2) - 4;
  Canvas.Pen.Color := clWindowText;
  Canvas.Pen.Width := 2;
  Canvas.Brush.Style := bsClear;
  Canvas.Ellipse(C.X - Radius, C.Y - Radius, C.X + Radius, C.Y + Radius);
  // While dragging the crosshair "is" the cursor, so the icon shows an empty ring
  if not FDragging then
  begin
    Canvas.Pen.Width := 1;
    Canvas.MoveTo(C.X, C.Y - Radius - 2);
    Canvas.LineTo(C.X, C.Y + Radius + 3);
    Canvas.MoveTo(C.X - Radius - 2, C.Y);
    Canvas.LineTo(C.X + Radius + 3, C.Y);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TFinderTool.WMLButtonDown(var Message: TWMLButtonDown);
begin
  FDragging := True;
  FLastWnd := 0;
  SetCapture(Handle);
  // Windows sends no WM_SETCURSOR while the mouse is captured, so this sticks
  Winapi.Windows.SetCursor(Screen.Cursors[crCross]);
  Invalidate;
end;

procedure TFinderTool.WMMouseMove(var Message: TWMMouseMove);
var
  Pt: TPoint;
begin
  if not FDragging then
  begin
    inherited;
    Exit;
  end;
  GetCursorPos(Pt);
  FLastWnd := WindowAtPoint(Pt);
  if Assigned(FOnPickMove) then
    FOnPickMove(Self, FLastWnd, Pt);
end;

procedure TFinderTool.WMLButtonUp(var Message: TWMLButtonUp);
var
  Pt: TPoint;
  Wnd: HWND;
begin
  if not FDragging then
  begin
    inherited;
    Exit;
  end;
  GetCursorPos(Pt);
  Wnd := WindowAtPoint(Pt);
  StopDragging;
  if Wnd = 0 then
  begin
    if Assigned(FOnPickCancel) then
      FOnPickCancel(Self);
  end
  else if Assigned(FOnPickDone) then
    FOnPickDone(Self, Wnd, Pt);
end;

procedure TFinderTool.WMRButtonDown(var Message: TWMRButtonDown);
begin
  if not FDragging then
  begin
    inherited;
    Exit;
  end;
  StopDragging;
  if Assigned(FOnPickCancel) then
    FOnPickCancel(Self);
end;

procedure TFinderTool.WMCaptureChanged(var Message: TMessage);
begin
  inherited;
  // Capture taken away (Alt+Tab, a popup...) while dragging
  if FDragging and (HWND(Message.LParam) <> Handle) then
  begin
    FDragging := False;
    Invalidate;
    if Assigned(FOnPickCancel) then
      FOnPickCancel(Self);
  end;
end;

procedure TFinderTool.StopDragging;
begin
  FDragging := False;
  ReleaseCapture;
  Invalidate;
end;

{ THighlightFrame }

constructor THighlightFrame.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  Color := clRed;
  Scaled := False;
end;

procedure THighlightFrame.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.ExStyle := Params.ExStyle or WS_EX_TOPMOST or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE or
    WS_EX_TRANSPARENT;
  Params.WndParent := 0;
end;

procedure THighlightFrame.WMNCHitTest(var Message: TWMNCHitTest);
begin
  Message.Result := HTTRANSPARENT;
end;

procedure THighlightFrame.WMDpiChanged(var Message: TMessage);
begin
  // ShowAt always passes physical pixels; don't let VCL rescale the frame
  Message.Result := 0;
end;

procedure THighlightFrame.ShowAt(const R: TRect);
var
  Region, Inner: HRGN;
begin
  if (R.Width <= 0) or (R.Height <= 0) then
  begin
    HideFrame;
    Exit;
  end;
  if (R.Width <> FSize.cx) or (R.Height <> FSize.cy) then
  begin
    FSize := TSize.Create(R.Width, R.Height);
    Region := CreateRectRgn(0, 0, R.Width, R.Height);
    if (R.Width > 2 * FrameWidth) and (R.Height > 2 * FrameWidth) then
    begin
      Inner := CreateRectRgn(FrameWidth, FrameWidth, R.Width - FrameWidth, R.Height - FrameWidth);
      CombineRgn(Region, Region, Inner, RGN_DIFF);
      DeleteObject(Inner);
    end;
    SetWindowRgn(Handle, Region, True); // the system owns Region now
  end;
  SetWindowPos(Handle, HWND_TOPMOST, R.Left, R.Top, R.Width, R.Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);
end;

procedure THighlightFrame.HideFrame;
begin
  if HandleAllocated then
    ShowWindow(Handle, SW_HIDE);
end;

end.
