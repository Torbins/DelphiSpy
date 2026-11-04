unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Types, System.JSON,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics,
  Finder, InjectRunner;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    pnlFinder: TPanel;
    lblHint: TLabel;
    lblTarget: TLabel;
    chkStayOnTop: TCheckBox;
    btnCopyName: TButton;
    btnCopyJson: TButton;
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
    tabHierarchy: TTabSheet;
    tvHierarchy: TTreeView;
    tabJson: TTabSheet;
    memJson: TMemo;
    tabHistory: TTabSheet;
    lbHistory: TListBox;
    sbStatus: TStatusBar;
    tmrFlash: TTimer;
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
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FFinder: TFinderTool;
    FFrame: THighlightFrame;
    FRunner: TInjectRunner;
    FHoverWnd: HWND;
    FReport: TJSONObject;
    FHistoryJson: TStringList; // parallel to lbHistory.Items, newest first
    // The edit in flight, to reopen the editor with it if the target refuses it
    FEditName, FEditText: string;
    FSelectedName: string; // reselected when the property list is filled again
    procedure FinderPickMove(Sender: TObject; Wnd: HWND; const ScreenPt: TPoint);
    procedure FinderPickDone(Sender: TObject; Wnd: HWND; const ScreenPt: TPoint);
    procedure FinderPickCancel(Sender: TObject);
    procedure RunnerDone(Sender: TObject);
    procedure RequestDone(Sender: TObject);
    procedure StartInspection(Wnd: HWND; const ScreenPt: TPoint);
    function StartRequest(Request: TJSONObject): Boolean;
    function ReportOk: Boolean;
    function SelectedProperty: TJSONObject;
    function FindProperty(const Name: string): TJSONObject;
    procedure EditProperty(Prop: TJSONObject; const Text, Error: string);
    procedure UpdatePropertyButtons;
    procedure ShowReport(const Json: string; AddToHistory: Boolean);
    procedure ShowError(const Msg: string);
    procedure ShowInfo(const Msg: string);
    procedure ClearDetails;
    procedure FillProperties;
    procedure FillEvents(Control: TJSONObject);
    procedure FillHierarchy(Control: TJSONObject);
    procedure FlashRect(const R: TRect);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  System.Generics.Collections, System.UITypes, Vcl.Clipbrd, PropEditor;

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

function NameOrClass(Obj: TJSONObject): string;
begin
  Result := JStr(Obj, 'name');
  if Result = '' then
    Result := '<unnamed>';
  Result := Result + ': ' + JStr(Obj, 'className');
end;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FHistoryJson := TStringList.Create;
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
  FReport.Free;
  FHistoryJson.Free;
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
  ShowReport(TInjectRunner(Sender).Output, True);
end;

procedure TfrmMain.ShowReport(const Json: string; AddToHistory: Boolean);
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
  FillHierarchy(Control);

  ShowInfo(Format('%s   PID %s   %s', [JStr(FReport, 'inspector'), JStr(FReport, 'process.pid'),
    JStr(FReport, 'process.exe')]));

  ScreenRect := JObj(Control, 'screenRect');
  if ScreenRect <> nil then
    FlashRect(TRect.Create(ScreenRect.GetValue<Integer>('left'), ScreenRect.GetValue<Integer>('top'),
      ScreenRect.GetValue<Integer>('right'), ScreenRect.GetValue<Integer>('bottom')));

  if AddToHistory then
  begin
    HistoryCaption := Format('%s   %s   (%s)', [TimeToStr(Time), NameOrClass(Control),
      ExtractFileName(JStr(FReport, 'process.exe'))]);
    lbHistory.Items.Insert(0, HistoryCaption);
    FHistoryJson.Insert(0, Json);
    while FHistoryJson.Count > MaxHistory do
    begin
      FHistoryJson.Delete(FHistoryJson.Count - 1);
      lbHistory.Items.Delete(lbHistory.Items.Count - 1);
    end;
  end;
end;

procedure TfrmMain.ShowError(const Msg: string);
begin
  lblTarget.Font.Color := clRed;
  lblTarget.Caption := Msg;
  lblTarget.Hint := Msg;
  sbStatus.SimpleText := 'Error: ' + Msg;
end;

procedure TfrmMain.ShowInfo(const Msg: string);
begin
  lblTarget.Font.Color := clWindowText;
  lblTarget.Caption := Msg;
  lblTarget.Hint := Msg;
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
  tvHierarchy.Items.Clear;
  UpdatePropertyButtons;
end;

procedure TfrmMain.FillProperties;
var
  Props: TJSONArray;
  Element: TJSONValue;
  Prop: TJSONObject;
  Filter, Name, Value: string;
  Item, Selected: TListItem;
begin
  Props := JArr(JObj(FReport, 'control'), 'properties');
  Filter := LowerCase(Trim(edtFilter.Text));
  Selected := nil;
  lvProperties.Items.BeginUpdate;
  try
    lvProperties.Items.Clear;
    if Props <> nil then
      for Element in Props do
      begin
        Prop := Element as TJSONObject;
        Name := JStr(Prop, 'name');
        Value := JStr(Prop, 'value');
        if (Filter <> '') and (Pos(Filter, LowerCase(Name + ' ' + Value)) = 0) then
          Continue;
        Item := lvProperties.Items.Add;
        Item.Caption := Name;
        Item.SubItems.Add(Value);
        Item.SubItems.Add(JStr(Prop, 'type'));
        Item.SubItems.Add(JStr(Prop, 'scope'));
        Item.Data := Prop; // owned by FReport, which outlives the list items
        if SameText(Name, FSelectedName) then
          Selected := Item;
      end;
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

function TfrmMain.FindProperty(const Name: string): TJSONObject;
var
  Element: TJSONValue;
  Props: TJSONArray;
begin
  Props := JArr(JObj(FReport, 'control'), 'properties');
  if Props <> nil then
    for Element in Props do
      if SameText(JStr(Element as TJSONObject, 'name'), Name) then
        Exit(TJSONObject(Element));
  Result := nil;
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
  Info.Name := JStr(Prop, 'name');
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
    if StartRequest(Request) then
    begin
      FEditName := Info.Name;
      FEditText := NewText;
    end;
  finally
    Request.Free;
  end;
end;

function TfrmMain.StartRequest(Request: TJSONObject): Boolean;
var
  Wnd: HWND;
  Injector: string;
begin
  Result := False;
  if (FRunner <> nil) or not ReportOk then
    Exit;
  Wnd := HWND(FReport.GetValue<Int64>('window.hwnd', 0));
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
  Request.AddPair('address', JStr(FReport, 'control.address'));
  ShowInfo('Sending to ' + DescribeWindow(Wnd) + ' ...');
  Screen.Cursor := crHourGlass;
  FRunner := TInjectRunner.Create(Format('"%s" --hwnd %d --request -', [Injector, NativeUInt(Wnd)]),
    TEncoding.UTF8.GetBytes(Request.ToJSON), RequestDone);
end;

procedure TfrmMain.RequestDone(Sender: TObject);
var
  Json, Error, Name, Text: string;
  Value: TJSONValue;
  Changed: TJSONObject;
begin
  Screen.Cursor := crDefault;
  FRunner := nil;
  Json := TInjectRunner(Sender).Output;
  Name := FEditName;
  Text := FEditText;
  FEditName := '';
  FEditText := '';

  Value := TJSONObject.ParseJSONValue(Json);
  try
    if not (Value is TJSONObject) then
      Error := 'Unexpected output from the injector: ' + Json
    else if not TJSONObject(Value).GetValue<Boolean>('ok', False) then
      Error := JStr(TJSONObject(Value), 'error')
    else
      Error := '';
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
  finally
    Value.Free;
  end;

  ShowReport(Json, False);
  Changed := JObj(FReport, 'changed');
  if Changed <> nil then
    ShowInfo(Format('%s.%s changed from "%s" to "%s"', [JStr(FReport, 'control.path'),
      JStr(Changed, 'property'), JStr(Changed, 'oldValue'), JStr(Changed, 'newValue')]))
  else
    ShowInfo('Refreshed ' + JStr(FReport, 'control.path') + ' at ' + TimeToStr(Time));
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

procedure TfrmMain.FillHierarchy(Control: TJSONObject);

  function Flags(Obj: TJSONObject): string;
  begin
    Result := '';
    if not Obj.GetValue<Boolean>('visible', True) then
      Result := Result + '  [hidden]';
    if not Obj.GetValue<Boolean>('enabled', True) then
      Result := Result + '  [disabled]';
  end;

var
  Items: TTreeNodes;
  Node: TTreeNode;
  List: TJSONArray;
  Obj, Action: TJSONObject;
  I: Integer;
begin
  Items := tvHierarchy.Items;
  Items.BeginUpdate;
  try
    Items.Clear;

    Node := Items.Add(nil, 'Visual parents (Parent)');
    List := JArr(Control, 'parents');
    if List <> nil then
      for I := List.Count - 1 downto 0 do
      begin
        Obj := List.Items[I] as TJSONObject;
        Node := Items.AddChild(Node, NameOrClass(Obj) + Flags(Obj));
      end;
    Items.AddChild(Node, '> ' + NameOrClass(Control) + Flags(Control));

    Node := Items.Add(nil, 'Owners (Owner)');
    List := JArr(Control, 'owners');
    if List <> nil then
      for I := List.Count - 1 downto 0 do
      begin
        Obj := List.Items[I] as TJSONObject;
        Node := Items.AddChild(Node, Format('%s   (%s, unit %s)', [NameOrClass(Obj),
          JStr(Obj, 'kind'), JStr(Obj, 'unitName')]));
      end;
    Items.AddChild(Node, '> ' + NameOrClass(Control));

    Node := Items.Add(nil, 'Class hierarchy');
    List := JArr(Control, 'classHierarchy');
    if List <> nil then
      for I := List.Count - 1 downto 0 do
      begin
        Obj := List.Items[I] as TJSONObject;
        Node := Items.AddChild(Node, Format('%s   (unit %s, %s)', [JStr(Obj, 'className'),
          JStr(Obj, 'unitName'), JStr(Obj, 'module')]));
      end;

    Action := JObj(Control, 'action');
    if Action <> nil then
      Items.Add(nil, Format('Action: %s: %s', [JStr(Action, 'path'), JStr(Action, 'className')]));

    tvHierarchy.FullExpand;
  finally
    Items.EndUpdate;
  end;
  if Items.Count > 0 then
    Items[0].MakeVisible;
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
    StartRequest(Request);
  finally
    Request.Free;
  end;
end;

procedure TfrmMain.lvPropertiesDblClick(Sender: TObject);
begin
  btnEditClick(nil);
end;

procedure TfrmMain.lvPropertiesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) or (Key = VK_F2) then
  begin
    Key := 0;
    btnEditClick(nil);
  end;
end;

procedure TfrmMain.lvPropertiesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then
    FSelectedName := Item.Caption;
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
  end;
end;

procedure TfrmMain.lbHistoryClick(Sender: TObject);
begin
  if lbHistory.ItemIndex >= 0 then
    ShowReport(FHistoryJson[lbHistory.ItemIndex], False);
end;

end.
