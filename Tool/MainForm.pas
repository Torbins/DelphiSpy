unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Types, System.JSON,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus,
  Finder, InjectRunner, VclSpy.RemoteClient;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    pnlFinder: TPanel;
    lblHint: TLabel;
    lblTarget: TLabel;
    chkStayOnTop: TCheckBox;
    btnCopyName: TButton;
    btnCopyJson: TButton;
    btnConnect: TButton;
    btnForms: TButton;
    pnlSummary: TPanel;
    lblName: TLabel;
    edtName: TEdit;
    lblClass: TLabel;
    edtClass: TEdit;
    lblUnit: TLabel;
    edtUnit: TEdit;
    lblForm: TLabel;
    edtForm: TEdit;
    lblPath: TLabel;
    edtPath: TEdit;
    lblParents: TLabel;
    edtParents: TEdit;
    lblModule: TLabel;
    edtModule: TEdit;
    lblText: TLabel;
    edtText: TEdit;
    pgcDetails: TPageControl;
    tabProperties: TTabSheet;
    pnlPropTools: TPanel;
    edtFilter: TEdit;
    btnEdit: TButton;
    btnRefresh: TButton;
    lvProperties: TListView;
    tabEvents: TTabSheet;
    lvEvents: TListView;
    tabParents: TTabSheet;
    tvParents: TTreeView;
    tabOwners: TTabSheet;
    tvOwners: TTreeView;
    tabClasses: TTabSheet;
    tvClasses: TTreeView;
    tabJson: TTabSheet;
    memJson: TMemo;
    tabHistory: TTabSheet;
    lbHistory: TListBox;
    sbStatus: TStatusBar;
    tmrFlash: TTimer;
    tmrSelect: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure chkStayOnTopClick(Sender: TObject);
    procedure btnCopyNameClick(Sender: TObject);
    procedure btnCopyJsonClick(Sender: TObject);
    procedure edtFilterChange(Sender: TObject);
    procedure lbHistoryClick(Sender: TObject);
    procedure tmrFlashTimer(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure lvPropertiesDblClick(Sender: TObject);
    procedure lvPropertiesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure lvPropertiesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvPropertiesCustomDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure lvPropertiesMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure tvParentsCreateNodeClass(Sender: TCustomTreeView; var NodeClass: TTreeNodeClass);
    procedure tvParentsExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    procedure tvParentsChange(Sender: TObject; Node: TTreeNode);
    procedure tmrSelectTimer(Sender: TObject);
    procedure btnConnectClick(Sender: TObject);
    procedure btnFormsClick(Sender: TObject);
  private
    FFinder: TFinderTool;
    FFrame: THighlightFrame;
    FRunner: TRequestRunner;
    // Connects to applications that link VclSpy.Server; created on first use
    FClient: TRemoteClient;
    // The TRemoteServer.ManagerId of the server FReport came from, '' for a
    // local target. Requests about the report go there.
    FReportServer: string;
    FHistoryServers: TStringList; // parallel to FHistoryJson
    FFormsMenu: TPopupMenu;
    FFormAddresses: TStringList; // of FFormsMenu's items, by Tag
    FDefaultHint: string;
    FHoverWnd: HWND;
    FReport: TJSONObject;
    FHistoryJson: TStringList; // parallel to lbHistory.Items, newest first
    // The edit in flight, to reopen the editor with it if the target refuses it
    FEditName, FEditText: string;
    FSelectedPath: string; // reselected when the property list is filled again
    // Paths of the object and record properties whose members are shown
    FExpanded: TStringList;
    FExpanderImages: TImageList;
    FFillingParents: Boolean; // tvParents selection changes are not the user's
    FExpandAddress: string; // the control whose children are being requested
    procedure FinderPickMove(Sender: TObject; Wnd: HWND; const ScreenPt: TPoint);
    procedure FinderPickDone(Sender: TObject; Wnd: HWND; const ScreenPt: TPoint);
    procedure FinderPickCancel(Sender: TObject);
    procedure RunnerDone(Sender: TObject);
    procedure RequestDone(Sender: TObject);
    procedure ChildrenDone(Sender: TObject);
    procedure SelectDone(Sender: TObject);
    procedure FormsDone(Sender: TObject);
    procedure FormsMenuClick(Sender: TObject);
    procedure StartInspection(Wnd: HWND; const ScreenPt: TPoint);
    function StartRequest(Request: TJSONObject; OnDone: TNotifyEvent): Boolean;
    function StartRemoteRequest(Request: TJSONObject; OnDone: TNotifyEvent): Boolean;
    function RemoteConnected: Boolean;
    procedure PickRemote;
    procedure UpdateRemoteUI;
    procedure ServerGone;
    function ReportOk: Boolean;
    function SelectedProperty: TJSONObject;
    function FindProperty(const Path: string): TJSONObject;
    procedure EditProperty(Prop: TJSONObject; const Text, Error: string);
    procedure EditOrToggle(Prop: TJSONObject);
    procedure SetExpanded(Prop: TJSONObject; Expand: Boolean);
    procedure SelectPath(const Path: string);
    procedure CreateExpanderImages;
    procedure FormAfterMonitorDpiChanged(Sender: TObject; OldDPI, NewDPI: Integer);
    procedure UpdatePropertyButtons;
    procedure ShowReport(const Json: string; AddToHistory: Boolean; const Server: string);
    procedure ShowError(const Msg: string);
    procedure ShowInfo(const Msg: string);
    procedure ClearDetails;
    procedure FillProperties;
    procedure FillEvents(Control: TJSONObject);
    procedure FillParents(Control: TJSONObject);
    procedure FillOwners(Control: TJSONObject);
    procedure FillClasses(Control: TJSONObject);
    procedure FlashRect(const R: TRect);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  System.Generics.Collections, System.UITypes, System.Math, Vcl.Clipbrd, PropEditor, ConnectForm;

const
  MaxHistory = 30;
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

function QueryFullProcessImageName(Process: THandle; Flags: DWORD; ExeName: PChar;
  var Size: DWORD): BOOL; stdcall; external kernel32 name 'QueryFullProcessImageNameW';

function ProcessExeName(Pid: DWORD): string;
var
  Process: THandle;
  Buffer: array[0..MAX_PATH] of Char;
  Size: DWORD;
begin
  Result := '';
  Process := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, Pid);
  if Process = 0 then
    Exit;
  try
    Size := Length(Buffer);
    if QueryFullProcessImageName(Process, 0, Buffer, Size) then
      SetString(Result, Buffer, Size);
  finally
    CloseHandle(Process);
  end;
end;

function DescribeWindow(Wnd: HWND): string;
var
  Buffer: array[0..255] of Char;
  ClassName, Text: string;
  Pid: DWORD;
begin
  SetString(ClassName, Buffer, GetClassName(Wnd, Buffer, Length(Buffer)));
  SetString(Text, Buffer, GetWindowText(Wnd, Buffer, Length(Buffer)));
  GetWindowThreadProcessId(Wnd, Pid);
  Result := Format('HWND $%.8x   %s   "%s"   PID %d %s',
    [Wnd, ClassName, Text, Pid, ExtractFileName(ProcessExeName(Pid))]);
end;

function JStr(Obj: TJSONObject; const Path: string): string;
begin
  if Obj = nil then
    Result := ''
  else
    Result := Obj.GetValue<string>(Path, '');
end;

function JObj(Obj: TJSONObject; const Path: string): TJSONObject;
begin
  Result := nil;
  if Obj <> nil then
    Result := Obj.GetValue<TJSONObject>(Path, nil);
end;

function JArr(Obj: TJSONObject; const Path: string): TJSONArray;
begin
  Result := nil;
  if Obj <> nil then
    Result := Obj.GetValue<TJSONArray>(Path, nil);
end;

// FMX style objects have a StyleName rather than a name
function NameOrClass(Obj: TJSONObject): string;
begin
  Result := JStr(Obj, 'name');
  if (Result = '') and (JStr(Obj, 'styleName') <> '') then
    Result := '''' + JStr(Obj, 'styleName') + ''''
  else if Result = '' then
    Result := '<unnamed>';
  Result := Result + ': ' + JStr(Obj, 'className');
end;

function ControlFlags(Obj: TJSONObject): string;
begin
  Result := '';
  if not Obj.GetValue<Boolean>('visible', True) then
    Result := Result + '  [hidden]';
  if not Obj.GetValue<Boolean>('enabled', True) then
    Result := Result + '  [disabled]';
  // Part of an FMX control's style
  if Obj.GetValue<Boolean>('style', False) then
    Result := Result + '  [style]';
end;

// The reply to a request, or nil with the reason in Error
function ParseReply(const Json: string; out Error: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  Value := TJSONObject.ParseJSONValue(Json);
  if not (Value is TJSONObject) then
    Error := 'Unexpected output from the injector: ' + Json
  else if not TJSONObject(Value).GetValue<Boolean>('ok', False) then
    Error := JStr(TJSONObject(Value), 'error')
  else
  begin
    Error := '';
    Exit(TJSONObject(Value));
  end;
  Value.Free;
end;

type
  // A control in tvParents. Its children are added when it is first unfolded.
  TControlNode = class(TTreeNode)
  public
    Address: string;
    Loaded: Boolean; // children added
  end;

function AddControlNode(Tree: TTreeView; Parent: TTreeNode; Obj: TJSONObject): TControlNode;
begin
  Result := Tree.Items.AddChild(Parent, NameOrClass(Obj) + ControlFlags(Obj)) as TControlNode;
  Result.Address := JStr(Obj, 'address');
  Result.HasChildren := Obj.GetValue<Integer>('childCount', 0) > 0;
end;

procedure AddChildNodes(Tree: TTreeView; Node: TControlNode; Children: TJSONArray);
var
  Element: TJSONValue;
begin
  if Children <> nil then
    for Element in Children do
      AddControlNode(Tree, Node, Element as TJSONObject);
  Node.Loaded := True;
  Node.HasChildren := Node.Count > 0;
end;

function FindChildNode(Node: TTreeNode; const Address: string): TControlNode;
begin
  Node := Node.getFirstChild;
  while Node <> nil do
  begin
    if TControlNode(Node).Address = Address then
      Exit(TControlNode(Node));
    Node := Node.getNextSibling;
  end;
  Result := nil;
end;

const
  // FExpanderImages
  imgExpand = 0;
  imgCollapse = 1;
  imgNone = 2;

// "Font.Size", "Panels[0].Width". Reports of older inspectors have names only.
function PropPath(Prop: TJSONObject): string;
begin
  Result := JStr(Prop, 'path');
  if Result = '' then
    Result := JStr(Prop, 'name');
end;

// The properties of an object property, or the fields of a record property;
// nil for other properties
function PropMembers(Prop: TJSONObject): TJSONArray;
begin
  Result := JArr(Prop, 'properties');
end;

// "Font" for "Font.Size", "Panels" for "Panels[0]", '' for "Font"
function ParentPropPath(const Path: string): string;
var
  I: Integer;
begin
  for I := Length(Path) downto 1 do
    if (Path[I] = '.') or (Path[I] = '[') then
      Exit(Copy(Path, 1, I - 1));
  Result := '';
end;

function FindPropIn(Props: TJSONArray; const Path: string): TJSONObject;
var
  Element: TJSONValue;
begin
  if Props <> nil then
    for Element in Props do
    begin
      Result := Element as TJSONObject;
      if SameText(PropPath(Result), Path) then
        Exit;
      Result := FindPropIn(PropMembers(Result), Path);
      if Result <> nil then
        Exit;
    end;
  Result := nil;
end;

// Each caption becomes a child of the one before it, outermost first
procedure FillChain(Tree: TTreeView; const Captions: TArray<string>);
var
  Node: TTreeNode;
  Caption: string;
begin
  Tree.Items.BeginUpdate;
  try
    Tree.Items.Clear;
    Node := nil;
    for Caption in Captions do
      Node := Tree.Items.AddChild(Node, Caption);
    Tree.FullExpand;
  finally
    Tree.Items.EndUpdate;
  end;
  if Tree.Items.Count > 0 then
    Tree.Items[0].MakeVisible;
end;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FHistoryJson := TStringList.Create;
  FHistoryServers := TStringList.Create;
  FFormAddresses := TStringList.Create;
  FFormsMenu := TPopupMenu.Create(Self);
  FDefaultHint := lblHint.Caption;
  FExpanded := TStringList.Create;
  FExpanded.Sorted := True;
  FExpanded.CaseSensitive := False;
  FExpanded.Duplicates := dupIgnore;
  CreateExpanderImages;
  OnAfterMonitorDpiChanged := FormAfterMonitorDpiChanged;
  FFrame := THighlightFrame.Create(Self);
  FFinder := TFinderTool.Create(Self);
  FFinder.Parent := pnlFinder;
  FFinder.Align := alClient;
  FFinder.Hint := 'Drag onto a control';
  FFinder.ShowHint := True;
  FFinder.OnPickMove := FinderPickMove;
  FFinder.OnPickDone := FinderPickDone;
  FFinder.OnPickCancel := FinderPickCancel;
  pgcDetails.ActivePage := tabProperties;
  ClearDetails;

  // VclSpy.exe --inspect <hwnd> <x> <y>: inspect without dragging (scripting, tests)
  if (ParamCount >= 4) and SameText(ParamStr(1), '--inspect') then
    TThread.ForceQueue(nil,
      procedure
      begin
        StartInspection(HWND(StrToInt64(ParamStr(2))),
          TPoint.Create(StrToInt(ParamStr(3)), StrToInt(ParamStr(4))));
      end);
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  if FRunner <> nil then
    FRunner.OnTerminate := nil; // it frees itself; just don't call back into a dead form
  if FClient <> nil then
  begin
    FClient.OnDisconnected := nil;
    // A TRemoteRunner may still use it; the process ends anyway
    if FRunner = nil then
      FClient.Free;
  end;
  FReport.Free;
  FHistoryJson.Free;
  FHistoryServers.Free;
  FFormAddresses.Free;
  FExpanded.Free;
end;

// Plus and minus boxes for object and record properties, and a blank image
// that keeps the names of other properties in line
procedure TfrmMain.CreateExpanderImages;
var
  Size, Box, Line, I, MidX, MidY: Integer;
  R: TRect;
  Bmp: TBitmap;
begin
  Size := MulDiv(16, CurrentPPI, 96);
  Box := MulDiv(9, CurrentPPI, 96) or 1; // odd, to center the lines
  Line := Max(1, CurrentPPI div 96);
  if FExpanderImages = nil then
    FExpanderImages := TImageList.Create(Self);
  FExpanderImages.Clear;
  FExpanderImages.SetSize(Size, Size);
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(Size, Size);
    for I := imgExpand to imgNone do
    begin
      Bmp.Canvas.Brush.Color := clFuchsia;
      Bmp.Canvas.FillRect(Rect(0, 0, Size, Size));
      if I <> imgNone then
      begin
        R := Bounds((Size - Box) div 2, (Size - Box) div 2, Box, Box);
        Bmp.Canvas.Pen.Color := clGrayText;
        Bmp.Canvas.Brush.Color := clWindow;
        Bmp.Canvas.Rectangle(R);
        MidX := R.Left + Box div 2 - Line div 2;
        MidY := R.Top + Box div 2 - Line div 2;
        Bmp.Canvas.Brush.Color := clWindowText;
        Bmp.Canvas.FillRect(Rect(R.Left + 2 * Line, MidY, R.Right - 2 * Line, MidY + Line));
        if I = imgExpand then
          Bmp.Canvas.FillRect(Rect(MidX, R.Top + 2 * Line, MidX + Line, R.Bottom - 2 * Line));
      end;
      FExpanderImages.AddMasked(Bmp, clFuchsia);
    end;
  finally
    Bmp.Free;
  end;
  lvProperties.SmallImages := FExpanderImages;
end;

procedure TfrmMain.FormAfterMonitorDpiChanged(Sender: TObject; OldDPI, NewDPI: Integer);
begin
  CreateExpanderImages;
  FillProperties;
end;

procedure TfrmMain.FinderPickMove(Sender: TObject; Wnd: HWND; const ScreenPt: TPoint);
var
  R: TRect;
begin
  if Wnd = FHoverWnd then
    Exit;
  FHoverWnd := Wnd;
  if Wnd = 0 then
  begin
    FFrame.HideFrame;
    ShowInfo('No window under the cursor.');
    Exit;
  end;
  GetWindowRect(Wnd, R);
  FFrame.ShowAt(R);
  ShowInfo(DescribeWindow(Wnd));
end;

procedure TfrmMain.FinderPickDone(Sender: TObject; Wnd: HWND; const ScreenPt: TPoint);
begin
  FFrame.HideFrame;
  FHoverWnd := 0;
  StartInspection(Wnd, ScreenPt);
end;

procedure TfrmMain.FinderPickCancel(Sender: TObject);
begin
  FFrame.HideFrame;
  FHoverWnd := 0;
  ShowInfo('Pick cancelled.');
end;

procedure TfrmMain.StartInspection(Wnd: HWND; const ScreenPt: TPoint);
var
  Injector: string;
begin
  if FRunner <> nil then
    Exit;
  try
    Injector := InjectorFor(Wnd);
  except
    on E: Exception do
    begin
      ShowError(E.Message);
      Exit;
    end;
  end;
  ShowInfo('Inspecting ' + DescribeWindow(Wnd) + ' ...');
  Screen.Cursor := crHourGlass;
  FRunner := TInjectRunner.Create(Format('"%s" --hwnd %d --x %d --y %d',
    [Injector, NativeUInt(Wnd), ScreenPt.X, ScreenPt.Y]), RunnerDone);
end;

procedure TfrmMain.RunnerDone(Sender: TObject);
begin
  Screen.Cursor := crDefault;
  FRunner := nil;
  ShowReport(TRequestRunner(Sender).Output, True, TRequestRunner(Sender).Server);
end;

procedure TfrmMain.ShowReport(const Json: string; AddToHistory: Boolean; const Server: string);
var
  Value: TJSONValue;
  Control, Form: TJSONObject;
  HistoryCaption: string;
  ScreenRect: TJSONObject;
begin
  Value := TJSONObject.ParseJSONValue(Json);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    ClearDetails;
    memJson.Text := Json;
    ShowError('Unexpected output from the injector (see the JSON tab).');
    Exit;
  end;
  FReport.Free;
  FReport := TJSONObject(Value);
  FReportServer := Server;
  ClearDetails;
  memJson.Text := FReport.Format(2);

  if not FReport.GetValue<Boolean>('ok', False) then
  begin
    ShowError(JStr(FReport, 'error'));
    Exit;
  end;

  Control := JObj(FReport, 'control');
  edtName.Text := JStr(Control, 'name');
  if edtName.Text = '' then
    edtName.Text := '(no name)';
  edtClass.Text := JStr(Control, 'className');
  edtUnit.Text := JStr(Control, 'unitName');
  Form := JObj(Control, 'form');
  if Form <> nil then
    edtForm.Text := Format('%s   (unit %s, %s)', [NameOrClass(Form), JStr(Form, 'unitName'),
      JStr(Form, 'module')]);
  edtPath.Text := JStr(Control, 'path');
  edtParents.Text := JStr(Control, 'parentPath');
  edtModule.Text := JStr(Control, 'module');
  edtText.Text := JStr(Control, 'text');
  FillProperties;
  FillEvents(Control);
  FillParents(Control);
  FillOwners(Control);
  FillClasses(Control);

  if Server <> '' then
    lblTarget.Caption := Format('%s   PID %s   %s   on %s (remote)', [JStr(FReport, 'inspector'),
      JStr(FReport, 'process.pid'), JStr(FReport, 'process.exe'), JStr(FReport, 'process.computer')])
  else
    lblTarget.Caption := Format('%s   PID %s   %s', [JStr(FReport, 'inspector'), JStr(FReport, 'process.pid'),
      JStr(FReport, 'process.exe')]);

  // The screen of a remote target is not this one
  ScreenRect := JObj(Control, 'screenRect');
  if (ScreenRect <> nil) and (Server = '') then
    FlashRect(TRect.Create(ScreenRect.GetValue<Integer>('left'), ScreenRect.GetValue<Integer>('top'),
      ScreenRect.GetValue<Integer>('right'), ScreenRect.GetValue<Integer>('bottom')));

  if AddToHistory then
  begin
    HistoryCaption := Format('%s   %s   (%s)', [TimeToStr(Time), NameOrClass(Control),
      ExtractFileName(JStr(FReport, 'process.exe'))]);
    lbHistory.Items.Insert(0, HistoryCaption);
    FHistoryJson.Insert(0, Json);
    FHistoryServers.Insert(0, Server);
    while FHistoryJson.Count > MaxHistory do
    begin
      FHistoryJson.Delete(FHistoryJson.Count - 1);
      FHistoryServers.Delete(FHistoryServers.Count - 1);
      lbHistory.Items.Delete(lbHistory.Items.Count - 1);
    end;
  end;
end;

procedure TfrmMain.ShowError(const Msg: string);
begin
  sbStatus.Font.Color := clRed;
  sbStatus.SimpleText := 'Error: ' + Msg;
end;

procedure TfrmMain.ShowInfo(const Msg: string);
begin
  sbStatus.Font.Color := clWindowText;
  sbStatus.SimpleText := Msg;
end;

procedure TfrmMain.ClearDetails;
begin
  edtName.Text := '';
  edtClass.Text := '';
  edtUnit.Text := '';
  edtForm.Text := '';
  edtPath.Text := '';
  edtParents.Text := '';
  edtModule.Text := '';
  edtText.Text := '';
  lvProperties.Items.Clear;
  lvEvents.Items.Clear;
  FFillingParents := True;
  try
    tvParents.Items.Clear;
  finally
    FFillingParents := False;
  end;
  tvOwners.Items.Clear;
  tvClasses.Items.Clear;
  UpdatePropertyButtons;
end;

// The properties as a tree: the members of object and record properties
// below them, indented, shown once unfolded. With a filter, every property
// that matches is listed by its path, also those of folded ones.
procedure TfrmMain.FillProperties;
var
  Filter: string;
  Selected: TListItem;

  procedure AddRows(Props: TJSONArray; Level: Integer);
  var
    Element: TJSONValue;
    Prop: TJSONObject;
    Members: TJSONArray;
    Path, Value: string;
    Item: TListItem;
    Unfolded: Boolean;
  begin
    for Element in Props do
    begin
      Prop := Element as TJSONObject;
      Path := PropPath(Prop);
      Value := JStr(Prop, 'value');
      Members := PropMembers(Prop);
      Unfolded := (Filter = '') and (Members <> nil) and (FExpanded.IndexOf(Path) >= 0);
      if (Filter = '') or (Pos(Filter, LowerCase(Path + ' ' + Value)) > 0) then
      begin
        Item := lvProperties.Items.Add;
        if Filter = '' then
        begin
          Item.Caption := JStr(Prop, 'name');
          Item.Indent := Level;
          if Members = nil then
            Item.ImageIndex := imgNone
          else if Unfolded then
            Item.ImageIndex := imgCollapse
          else
            Item.ImageIndex := imgExpand;
        end
        else
        begin
          Item.Caption := Path;
          Item.ImageIndex := imgNone;
        end;
        Item.SubItems.Add(Value);
        Item.SubItems.Add(JStr(Prop, 'type'));
        Item.SubItems.Add(JStr(Prop, 'scope'));
        Item.Data := Prop; // owned by FReport, which outlives the list items
        if SameText(Path, FSelectedPath) then
          Selected := Item;
      end;
      if (Members <> nil) and ((Filter <> '') or Unfolded) then
        AddRows(Members, Level + 1);
    end;
  end;

var
  Props: TJSONArray;
begin
  Props := JArr(JObj(FReport, 'control'), 'properties');
  Filter := LowerCase(Trim(edtFilter.Text));
  Selected := nil;
  lvProperties.Items.BeginUpdate;
  try
    lvProperties.Items.Clear;
    if Props <> nil then
      AddRows(Props, 0);
  finally
    lvProperties.Items.EndUpdate;
  end;
  if Selected <> nil then
  begin
    Selected.Selected := True;
    Selected.Focused := True;
    Selected.MakeVisible(False);
  end;
  UpdatePropertyButtons;
end;

function TfrmMain.ReportOk: Boolean;
begin
  Result := (FReport <> nil) and FReport.GetValue<Boolean>('ok', False);
end;

function TfrmMain.SelectedProperty: TJSONObject;
begin
  if lvProperties.Selected = nil then
    Result := nil
  else
    Result := TJSONObject(lvProperties.Selected.Data);
end;

function TfrmMain.FindProperty(const Path: string): TJSONObject;
begin
  Result := FindPropIn(JArr(JObj(FReport, 'control'), 'properties'), Path);
end;

procedure TfrmMain.SetExpanded(Prop: TJSONObject; Expand: Boolean);
var
  Path: string;
  I: Integer;
begin
  if (Prop = nil) or (PropMembers(Prop) = nil) then
    Exit;
  Path := PropPath(Prop);
  if Expand then
    FExpanded.Add(Path)
  else if FExpanded.Find(Path, I) then
    FExpanded.Delete(I);
  FSelectedPath := Path;
  FillProperties;
  // Scrolls the members into view, as far as the property itself stays in view
  if Expand and (lvProperties.Selected <> nil) then
  begin
    I := Min(lvProperties.Selected.Index + PropMembers(Prop).Count, lvProperties.Items.Count - 1);
    lvProperties.Items[I].MakeVisible(False);
    lvProperties.Selected.MakeVisible(False);
  end;
end;

procedure TfrmMain.SelectPath(const Path: string);
var
  Item: TListItem;
begin
  for Item in lvProperties.Items do
    if SameText(PropPath(TJSONObject(Item.Data)), Path) then
    begin
      Item.Selected := True;
      Item.Focused := True;
      Item.MakeVisible(False);
      Exit;
    end;
end;

// Edits a property, or folds or unfolds an object or record property
procedure TfrmMain.EditOrToggle(Prop: TJSONObject);
begin
  if Prop = nil then
    Exit;
  if Prop.GetValue<Boolean>('editable', False) then
    EditProperty(Prop, JStr(Prop, 'value'), '')
  else
    SetExpanded(Prop, FExpanded.IndexOf(PropPath(Prop)) < 0);
end;

procedure TfrmMain.UpdatePropertyButtons;
var
  Prop: TJSONObject;
begin
  Prop := SelectedProperty;
  btnEdit.Enabled := (Prop <> nil) and Prop.GetValue<Boolean>('editable', False);
  btnRefresh.Enabled := ReportOk;
end;

procedure TfrmMain.EditProperty(Prop: TJSONObject; const Text, Error: string);
var
  Info: TPropEditInfo;
  NewText: string;
  Request, Types: TJSONObject;
begin
  if (Prop = nil) or not Prop.GetValue<Boolean>('editable', False) or (FRunner <> nil) then
    Exit;
  Info.Name := PropPath(Prop);
  Info.TypeName := JStr(Prop, 'type');
  Info.Kind := JStr(Prop, 'kind');
  Info.Scope := JStr(Prop, 'scope');
  Info.Value := JStr(Prop, 'value');
  // By exact name: nested types are named like "TCustomButton.TButtonStyle",
  // which a path lookup (JArr) would split at the dot
  Info.Values := nil;
  Types := JObj(JObj(FReport, 'control'), 'types');
  if (Types <> nil) and (Types.GetValue(Info.TypeName) is TJSONArray) then
    Info.Values := TJSONArray(Types.GetValue(Info.TypeName));
  Info.Truncated := Prop.GetValue<Boolean>('truncated', False) and (Text = Info.Value);
  NewText := Text;
  if not PropEditor.EditProperty(Self, Info, NewText, Error) then
    Exit;

  Request := TJSONObject.Create;
  try
    Request.AddPair('op', 'set');
    Request.AddPair('property', Info.Name);
    Request.AddPair('value', NewText);
    if StartRequest(Request, RequestDone) then
    begin
      FEditName := Info.Name;
      FEditText := NewText;
    end;
  finally
    Request.Free;
  end;
end;

// Request goes to the reported control, unless it names another "address"
function TfrmMain.StartRequest(Request: TJSONObject; OnDone: TNotifyEvent): Boolean;
var
  Wnd: HWND;
  Injector: string;
begin
  Result := False;
  if (FRunner <> nil) or not ReportOk then
    Exit;
  if Request.GetValue('address') = nil then
    Request.AddPair('address', JStr(FReport, 'control.address'));
  Wnd := HWND(FReport.GetValue<Int64>('window.hwnd', 0));
  if FReportServer <> '' then
  begin
    if not RemoteConnected or (FClient.Server.ManagerId <> FReportServer) then
    begin
      ShowError(Format('Not connected to the application of this report (%s on %s). Connect to it again.',
        [ExtractFileName(JStr(FReport, 'process.exe')), JStr(FReport, 'process.computer')]));
      Exit;
    end;
    // Where the inspector looks for the control first
    Request.AddPair('hwnd', TJSONNumber.Create(Int64(Wnd)));
    Exit(StartRemoteRequest(Request, OnDone));
  end;
  if not IsWindow(Wnd) then
  begin
    ShowError('The target window no longer exists. Pick the control again.');
    Exit;
  end;
  try
    Injector := InjectorFor(Wnd);
  except
    on E: Exception do
    begin
      ShowError(E.Message);
      Exit;
    end;
  end;
  Result := True;
  ShowInfo('Sending to ' + DescribeWindow(Wnd) + ' ...');
  Screen.Cursor := crHourGlass;
  FRunner := TInjectRunner.Create(Format('"%s" --hwnd %d --request -', [Injector, NativeUInt(Wnd)]),
    TEncoding.UTF8.GetBytes(Request.ToJSON), OnDone);
end;

// Sends Request to the connected VclSpy.Server
function TfrmMain.StartRemoteRequest(Request: TJSONObject; OnDone: TNotifyEvent): Boolean;
begin
  Result := False;
  if FRunner <> nil then
    Exit;
  if not RemoteConnected then
  begin
    ShowError('Not connected to an application. Connect to one first.');
    Exit;
  end;
  ShowInfo('Sending to ' + FClient.Server.Caption + ' ...');
  Screen.Cursor := crHourGlass;
  FRunner := TRemoteRunner.Create(FClient, Request.ToJSON, OnDone);
  Result := True;
end;

procedure TfrmMain.RequestDone(Sender: TObject);
var
  Json, Error, Name, Text: string;
  Changed: TJSONObject;
begin
  Screen.Cursor := crDefault;
  FRunner := nil;
  Json := TRequestRunner(Sender).Output;
  Name := FEditName;
  Text := FEditText;
  FEditName := '';
  FEditText := '';

  ParseReply(Json, Error).Free;
  if Error <> '' then
  begin
    // Keep showing the last good report
    ShowError(Error);
    if Name <> '' then
      // Not from inside this OnTerminate handler: the runner thread waits for it
      TThread.ForceQueue(nil,
        procedure
        begin
          EditProperty(FindProperty(Name), Text, Error);
        end);
    Exit;
  end;

  ShowReport(Json, False, TRequestRunner(Sender).Server);
  Changed := JObj(FReport, 'changed');
  if Changed <> nil then
    ShowInfo(Format('%s.%s changed from "%s" to "%s"', [JStr(FReport, 'control.path'),
      JStr(Changed, 'property'), JStr(Changed, 'oldValue'), JStr(Changed, 'newValue')]))
  else
    ShowInfo('Refreshed ' + JStr(FReport, 'control.path') + ' at ' + TimeToStr(Time));
end;

procedure TfrmMain.ChildrenDone(Sender: TObject);
var
  Address, Error: string;
  Reply: TJSONObject;
  Node: TTreeNode;
begin
  Screen.Cursor := crDefault;
  FRunner := nil;
  Address := FExpandAddress;
  FExpandAddress := '';
  Reply := ParseReply(TRequestRunner(Sender).Output, Error);
  try
    if Reply = nil then
    begin
      ShowError(Error);
      Exit;
    end;
    // By address: the tree may have been filled again meanwhile (a history click)
    Node := tvParents.Items.GetFirstNode;
    while (Node <> nil) and ((TControlNode(Node).Address <> Address) or TControlNode(Node).Loaded) do
      Node := Node.GetNext;
    if Node = nil then
      Exit;
    tvParents.Items.BeginUpdate;
    try
      AddChildNodes(tvParents, TControlNode(Node), JArr(Reply, 'children'));
    finally
      tvParents.Items.EndUpdate;
    end;
    Node.Expand(False);
    ShowInfo(Format('%s: %d children', [Node.Text, Node.Count]));
  finally
    Reply.Free;
  end;
end;

procedure TfrmMain.SelectDone(Sender: TObject);
var
  Json, Error: string;
begin
  Screen.Cursor := crDefault;
  FRunner := nil;
  Json := TRequestRunner(Sender).Output;
  ParseReply(Json, Error).Free;
  if Error <> '' then
    ShowError(Error) // keep showing the last good report
  else
  begin
    ShowReport(Json, True, TRequestRunner(Sender).Server);
    ShowInfo('Inspected ' + JStr(FReport, 'control.path'));
  end;
end;

{ Remote targets }

function TfrmMain.RemoteConnected: Boolean;
begin
  Result := (FClient <> nil) and FClient.Connected;
end;

procedure TfrmMain.UpdateRemoteUI;
begin
  if RemoteConnected then
  begin
    btnConnect.Caption := 'Disconnect';
    lblHint.Caption := Format('Connected to %s. Forms... lists its forms; F6 inspects the control at ' +
      'its mouse cursor.', [FClient.Server.Caption]);
  end
  else
  begin
    btnConnect.Caption := 'Connect...';
    lblHint.Caption := FDefaultHint;
  end;
  lblHint.Hint := lblHint.Caption;
  btnForms.Enabled := RemoteConnected;
end;

// On the main thread, after the server closed the connection
procedure TfrmMain.ServerGone;
begin
  UpdateRemoteUI;
  ShowError('The connection to the remote application was closed.');
end;

procedure TfrmMain.btnConnectClick(Sender: TObject);
begin
  // A TRemoteRunner uses the connection
  if FRunner <> nil then
    Exit;
  if RemoteConnected then
  begin
    FClient.Disconnect;
    UpdateRemoteUI;
    ShowInfo('Disconnected.');
    Exit;
  end;
  if FClient = nil then
    try
      FClient := TRemoteClient.Create;
      FClient.OnDisconnected :=
        procedure
        begin
          TThread.Queue(nil, ServerGone);
        end;
    except
      on E: Exception do
      begin
        ShowError('App Tethering does not start: ' + E.Message);
        Exit;
      end;
    end;
  if not ConnectRemote(Self, FClient) then
    Exit;
  UpdateRemoteUI;
  ShowInfo('Connected to ' + FClient.Server.Caption + '.');
  btnFormsClick(nil);
end;

procedure TfrmMain.btnFormsClick(Sender: TObject);
var
  Request: TJSONObject;
begin
  Request := TJSONObject.Create;
  try
    Request.AddPair('op', 'forms');
    StartRemoteRequest(Request, FormsDone);
  finally
    Request.Free;
  end;
end;

procedure TfrmMain.PickRemote;
var
  Request: TJSONObject;
begin
  Request := TJSONObject.Create;
  try
    Request.AddPair('op', 'pick');
    StartRemoteRequest(Request, SelectDone);
  finally
    Request.Free;
  end;
end;

// Lists the forms in a menu below the Forms button, after the control at the
// mouse cursor
procedure TfrmMain.FormsDone(Sender: TObject);
var
  Reply, Form: TJSONObject;
  Forms: TJSONArray;
  Element: TJSONValue;
  Error, Caption: string;
  Item: TMenuItem;
  P: TPoint;
begin
  Screen.Cursor := crDefault;
  FRunner := nil;
  Reply := ParseReply(TRequestRunner(Sender).Output, Error);
  try
    if Reply = nil then
    begin
      ShowError(Error);
      Exit;
    end;
    FFormsMenu.Items.Clear;
    FFormAddresses.Clear;
    Item := TMenuItem.Create(FFormsMenu);
    Item.Caption := Format('Control at the mouse cursor of %s'#9'F6', [JStr(Reply, 'process.computer')]);
    Item.Tag := -1;
    Item.OnClick := FormsMenuClick;
    FFormsMenu.Items.Add(Item);
    FFormsMenu.Items.NewBottomLine;
    Forms := JArr(Reply, 'forms');
    if Forms <> nil then
      for Element in Forms do
      begin
        Form := Element as TJSONObject;
        Caption := NameOrClass(Form);
        if JStr(Form, 'caption') <> '' then
          Caption := Caption + '   "' + JStr(Form, 'caption') + '"';
        Item := TMenuItem.Create(FFormsMenu);
        // No accelerators from "&" in names and captions
        Item.Caption := StringReplace(Caption + ControlFlags(Form), '&', '&&', [rfReplaceAll]);
        Item.Tag := FFormAddresses.Add(JStr(Form, 'address'));
        Item.OnClick := FormsMenuClick;
        FFormsMenu.Items.Add(Item);
      end;
    ShowInfo(Format('%s: %d forms', [FClient.Server.Caption, FFormAddresses.Count]));
  finally
    Reply.Free;
  end;
  P := btnForms.ClientToScreen(Point(0, btnForms.Height));
  FFormsMenu.Popup(P.X, P.Y);
end;

procedure TfrmMain.FormsMenuClick(Sender: TObject);
var
  Index: Integer;
  Request: TJSONObject;
begin
  Index := TMenuItem(Sender).Tag;
  if Index < 0 then
  begin
    PickRemote;
    Exit;
  end;
  Request := TJSONObject.Create;
  try
    Request.AddPair('op', 'get');
    Request.AddPair('address', FFormAddresses[Index]);
    StartRemoteRequest(Request, SelectDone);
  finally
    Request.Free;
  end;
end;

procedure TfrmMain.FillEvents(Control: TJSONObject);

  procedure AddEvent(const Caption: string; Event: TJSONObject);
  var
    Item: TListItem;
  begin
    Item := lvEvents.Items.Add;
    Item.Caption := Caption;
    Item.SubItems.Add(JStr(Event, 'handler'));
    Item.SubItems.Add(JStr(Event, 'unitName'));
    Item.SubItems.Add(JStr(Event, 'instance'));
    Item.SubItems.Add(JStr(Event, 'address'));
    Item.SubItems.Add(JStr(Event, 'module'));
  end;

var
  Events: TJSONArray;
  Element: TJSONValue;
  OnExecute: TJSONObject;
begin
  lvEvents.Items.BeginUpdate;
  try
    Events := JArr(Control, 'events');
    if Events <> nil then
      for Element in Events do
        AddEvent(JStr(Element as TJSONObject, 'name'), Element as TJSONObject);
    OnExecute := JObj(Control, 'action.onExecute');
    if OnExecute <> nil then
      AddEvent(JStr(Control, 'action.name') + '.OnExecute', OnExecute);
  finally
    lvEvents.Items.EndUpdate;
  end;
  tabEvents.Caption := Format('Events (%d)', [lvEvents.Items.Count]);
end;

// The chain down to the control is unfolded, listing every child on the way.
// The rest, the control included, is unfolded on demand.
procedure TfrmMain.FillParents(Control: TJSONObject);
var
  List: TJSONArray;
  Next: TJSONObject;
  Node, Found: TControlNode;
  I: Integer;
begin
  List := JArr(Control, 'parents');
  FFillingParents := True;
  tvParents.Items.BeginUpdate;
  try
    tvParents.Items.Clear;
    if (List = nil) or (List.Count = 0) then
      Node := AddControlNode(tvParents, nil, Control)
    else
    begin
      Node := AddControlNode(tvParents, nil, List.Items[List.Count - 1] as TJSONObject);
      for I := List.Count - 1 downto 0 do
      begin
        if I > 0 then
          Next := List.Items[I - 1] as TJSONObject
        else
          Next := Control;
        AddChildNodes(tvParents, Node, JArr(List.Items[I] as TJSONObject, 'children'));
        Found := FindChildNode(Node, JStr(Next, 'address'));
        if Found = nil then
          Found := AddControlNode(tvParents, Node, Next);
        Node.Expand(False);
        Node := Found;
      end;
    end;
    AddChildNodes(tvParents, Node, JArr(Control, 'children'));
    Node.Text := '> ' + Node.Text;
    tvParents.Selected := Node;
  finally
    tvParents.Items.EndUpdate;
    FFillingParents := False;
  end;
  Node.MakeVisible;
end;

procedure TfrmMain.FillOwners(Control: TJSONObject);
var
  Captions: TArray<string>;
  List: TJSONArray;
  Obj, Action: TJSONObject;
  I: Integer;
begin
  List := JArr(Control, 'owners');
  if List <> nil then
    for I := List.Count - 1 downto 0 do
    begin
      Obj := List.Items[I] as TJSONObject;
      Captions := Captions + [Format('%s   (%s, unit %s)', [NameOrClass(Obj), JStr(Obj, 'kind'),
        JStr(Obj, 'unitName')])];
    end;
  FillChain(tvOwners, Captions + ['> ' + NameOrClass(Control)]);

  // Not part of the Owner chain, but it is also found by owner path
  Action := JObj(Control, 'action');
  if Action <> nil then
    tvOwners.Items.Add(nil, Format('Action: %s: %s', [JStr(Action, 'path'), JStr(Action, 'className')]));
end;

procedure TfrmMain.FillClasses(Control: TJSONObject);
var
  Captions: TArray<string>;
  List: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
begin
  List := JArr(Control, 'classHierarchy');
  if List <> nil then
    for I := List.Count - 1 downto 0 do
    begin
      Obj := List.Items[I] as TJSONObject;
      Captions := Captions + [Format('%s   (unit %s, %s)', [JStr(Obj, 'className'),
        JStr(Obj, 'unitName'), JStr(Obj, 'module')])];
    end;
  FillChain(tvClasses, Captions);
end;

procedure TfrmMain.FlashRect(const R: TRect);
begin
  tmrFlash.Enabled := False;
  FFrame.ShowAt(R);
  tmrFlash.Enabled := True;
end;

procedure TfrmMain.tmrFlashTimer(Sender: TObject);
begin
  tmrFlash.Enabled := False;
  if not FFinder.IsDragging then
    FFrame.HideFrame;
end;

procedure TfrmMain.chkStayOnTopClick(Sender: TObject);
begin
  if chkStayOnTop.Checked then
    FormStyle := fsStayOnTop
  else
    FormStyle := fsNormal;
end;

procedure TfrmMain.btnCopyNameClick(Sender: TObject);
begin
  if edtName.Text <> '' then
    Clipboard.AsText := edtName.Text;
end;

procedure TfrmMain.btnCopyJsonClick(Sender: TObject);
begin
  if memJson.Text <> '' then
    Clipboard.AsText := memJson.Text;
end;

procedure TfrmMain.edtFilterChange(Sender: TObject);
begin
  FillProperties;
end;

procedure TfrmMain.btnEditClick(Sender: TObject);
var
  Prop: TJSONObject;
begin
  Prop := SelectedProperty;
  if Prop <> nil then
    EditProperty(Prop, JStr(Prop, 'value'), '');
end;

procedure TfrmMain.btnRefreshClick(Sender: TObject);
var
  Request: TJSONObject;
begin
  Request := TJSONObject.Create;
  try
    Request.AddPair('op', 'get');
    StartRequest(Request, RequestDone);
  finally
    Request.Free;
  end;
end;

procedure TfrmMain.lvPropertiesDblClick(Sender: TObject);
var
  P: TPoint;
begin
  // The clicks on a plus or minus box folded or unfolded it already
  P := lvProperties.ScreenToClient(Mouse.CursorPos);
  if htOnIcon in lvProperties.GetHitTestInfoAt(P.X, P.Y) then
    Exit;
  EditOrToggle(SelectedProperty);
end;

procedure TfrmMain.lvPropertiesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Prop: TJSONObject;
  Unfolded: Boolean;
begin
  Prop := SelectedProperty;
  case Key of
    VK_RETURN, VK_F2:
      begin
        Key := 0;
        EditOrToggle(Prop);
      end;
    // Unfold, fold, or go to the object or record a member belongs to
    VK_RIGHT, VK_ADD, VK_LEFT, VK_SUBTRACT:
      if (Prop <> nil) and (Trim(edtFilter.Text) = '') then
      begin
        Unfolded := FExpanded.IndexOf(PropPath(Prop)) >= 0;
        if (Key = VK_RIGHT) or (Key = VK_ADD) then
        begin
          if (PropMembers(Prop) <> nil) and not Unfolded then
            SetExpanded(Prop, True);
        end
        else if (PropMembers(Prop) <> nil) and Unfolded then
          SetExpanded(Prop, False)
        else if ParentPropPath(PropPath(Prop)) <> '' then
          SelectPath(ParentPropPath(PropPath(Prop)));
        Key := 0;
      end;
  end;
end;

procedure TfrmMain.lvPropertiesMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Item: TListItem;
  Path: string;
begin
  if (Button <> mbLeft) or (ssDouble in Shift) or not (htOnIcon in lvProperties.GetHitTestInfoAt(X, Y)) then
    Exit;
  Item := lvProperties.GetItemAt(X, Y);
  if (Item = nil) or (PropMembers(TJSONObject(Item.Data)) = nil) then
    Exit;
  Path := PropPath(TJSONObject(Item.Data));
  // Not while the list view handles the click: this fills it again
  TThread.ForceQueue(nil,
    procedure
    begin
      SetExpanded(FindProperty(Path), FExpanded.IndexOf(Path) < 0);
    end);
end;

procedure TfrmMain.lvPropertiesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then
    FSelectedPath := PropPath(TJSONObject(Item.Data));
  UpdatePropertyButtons;
end;

procedure TfrmMain.lvPropertiesCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  if (Item.Data <> nil) and not TJSONObject(Item.Data).GetValue<Boolean>('editable', False) then
    Sender.Canvas.Font.Color := clGrayText;
end;

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F5) and (Shift = []) then
  begin
    Key := 0;
    btnRefreshClick(nil);
  end
  else if (Key = VK_F6) and (Shift = []) and RemoteConnected then
  begin
    Key := 0;
    PickRemote;
  end;
end;

procedure TfrmMain.tvParentsCreateNodeClass(Sender: TCustomTreeView;
  var NodeClass: TTreeNodeClass);
begin
  NodeClass := TControlNode;
end;

procedure TfrmMain.tvParentsExpanding(Sender: TObject; Node: TTreeNode;
  var AllowExpansion: Boolean);
var
  Request: TJSONObject;
begin
  if FFillingParents or TControlNode(Node).Loaded then
    Exit;
  // ChildrenDone unfolds it once the children are added
  AllowExpansion := False;
  if FRunner <> nil then
  begin
    ShowInfo('Busy with another request; unfold it again in a moment.');
    Exit;
  end;
  Request := TJSONObject.Create;
  try
    Request.AddPair('op', 'children');
    Request.AddPair('address', TControlNode(Node).Address);
    if StartRequest(Request, ChildrenDone) then
      FExpandAddress := TControlNode(Node).Address;
  finally
    Request.Free;
  end;
end;

procedure TfrmMain.tvParentsChange(Sender: TObject; Node: TTreeNode);
begin
  if FFillingParents then
    Exit;
  // Lets arrow keys settle before inspecting
  tmrSelect.Enabled := False;
  tmrSelect.Enabled := Node <> nil;
end;

procedure TfrmMain.tmrSelectTimer(Sender: TObject);
var
  Node: TControlNode;
  Request: TJSONObject;
begin
  if FRunner <> nil then
    Exit; // tries again on the next tick
  tmrSelect.Enabled := False;
  Node := TControlNode(tvParents.Selected);
  if (Node = nil) or (Node.Address = JStr(FReport, 'control.address')) then
    Exit;
  Request := TJSONObject.Create;
  try
    Request.AddPair('op', 'get');
    Request.AddPair('address', Node.Address);
    StartRequest(Request, SelectDone);
  finally
    Request.Free;
  end;
end;

procedure TfrmMain.lbHistoryClick(Sender: TObject);
begin
  if lbHistory.ItemIndex >= 0 then
    ShowReport(FHistoryJson[lbHistory.ItemIndex], False, FHistoryServers[lbHistory.ItemIndex]);
end;

end.
