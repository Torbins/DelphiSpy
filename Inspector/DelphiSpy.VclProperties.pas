unit DelphiSpy.VclProperties;

{ What the VCL inspector knows about VCL classes, registered with
  DelphiSpy.Properties and DelphiSpy.Members:

  - The TControl and TWinControl properties that are declared public or
    protected, so RTTI doesn't list them unless a class republishes them;
    access classes reach them instead (RegisterExtraProps).
  - Names of TColor, TCursor and TShortCut values (clRed, crHandPoint, Ctrl+S).
  - The items of list views and tree views, as items of a collection.
  - TPicture's getters that change the picture, which are not read.
  - Short summaries of fonts, list items and tree nodes. }

interface

implementation

uses
  System.SysUtils, System.Classes, System.TypInfo, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Menus, Vcl.ComCtrls,
  DelphiSpy.Properties, DelphiSpy.Members;

type
  TControlAccess = class(TControl);
  TWinControlAccess = class(TWinControl);

{ The TControl and TWinControl properties }

procedure AddOrd(const Name, Scope: string; Info: PTypeInfo; WinControlOnly: Boolean;
  const GetOrd: TFunc<TControl, Integer>; const SetOrd: TProc<TControl, Integer>);
var
  P: TExtraProp;
begin
  P := Default(TExtraProp);
  P.Name := Name;
  P.Scope := Scope;
  P.Info := Info;
  if WinControlOnly then
    P.Cls := TWinControl
  else
    P.Cls := TControl;
  P.GetOrd :=
    function(X: TObject): Integer
    begin
      Result := GetOrd(TControl(X));
    end;
  if Assigned(SetOrd) then
    P.SetOrd :=
      procedure(X: TObject; V: Integer)
      begin
        SetOrd(TControl(X), V);
      end;
  RegisterExtraProp(P);
end;

procedure AddStr(const Name, Scope: string; Info: PTypeInfo; WinControlOnly, KeepsString: Boolean;
  const GetStr: TFunc<TControl, string>; const SetStr: TProc<TControl, string>);
var
  P: TExtraProp;
begin
  P := Default(TExtraProp);
  P.Name := Name;
  P.Scope := Scope;
  P.Info := Info;
  if WinControlOnly then
    P.Cls := TWinControl
  else
    P.Cls := TControl;
  P.KeepsString := KeepsString;
  P.GetStr :=
    function(X: TObject): string
    begin
      Result := GetStr(TControl(X));
    end;
  P.SetStr :=
    procedure(X: TObject; V: string)
    begin
      SetStr(TControl(X), V);
    end;
  RegisterExtraProp(P);
end;

function C(Ctrl: TControl): TControlAccess; inline;
begin
  Result := TControlAccess(Ctrl);
end;

function W(Ctrl: TControl): TWinControlAccess; inline;
begin
  Result := TWinControlAccess(Ctrl);
end;

// What TControl publishes itself (Left, Top, Width, Height, Hint, Cursor...)
// comes from RTTI, like any published property.
procedure RegisterExtraProps;
const
  AnyControl = False;
  WinControl = True;
  // SetText hands the window a copy (WM_SETTEXT); the others store the string
  ByMessage = False;
  Keeps = True;
begin
  // TControl, public
  AddOrd('Visible', 'public', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.Visible) end,
    procedure(X: TControl; V: Integer) begin X.Visible := V <> 0 end);
  AddOrd('Enabled', 'public', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.Enabled) end,
    procedure(X: TControl; V: Integer) begin X.Enabled := V <> 0 end);
  AddOrd('Align', 'public', TypeInfo(TAlign), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.Align) end,
    procedure(X: TControl; V: Integer) begin X.Align := TAlign(V) end);
  AddOrd('Anchors', 'public', TypeInfo(TAnchors), AnyControl,
    function(X: TControl): Integer begin Result := Byte(X.Anchors) end,
    procedure(X: TControl; V: Integer) begin X.Anchors := TAnchors(Byte(V)) end);
  AddOrd('BiDiMode', 'public', TypeInfo(TBiDiMode), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.BiDiMode) end,
    procedure(X: TControl; V: Integer) begin X.BiDiMode := TBiDiMode(V) end);
  AddOrd('ClientWidth', 'public', TypeInfo(Integer), AnyControl,
    function(X: TControl): Integer begin Result := X.ClientWidth end,
    procedure(X: TControl; V: Integer) begin X.ClientWidth := V end);
  AddOrd('ClientHeight', 'public', TypeInfo(Integer), AnyControl,
    function(X: TControl): Integer begin Result := X.ClientHeight end,
    procedure(X: TControl; V: Integer) begin X.ClientHeight := V end);
  AddOrd('ShowHint', 'public', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(X.ShowHint) end,
    procedure(X: TControl; V: Integer) begin X.ShowHint := V <> 0 end);
  AddOrd('StyleElements', 'public', TypeInfo(TStyleElements), AnyControl,
    function(X: TControl): Integer begin Result := Byte(X.StyleElements) end,
    procedure(X: TControl; V: Integer) begin X.StyleElements := TStyleElements(Byte(V)) end);
  AddStr('StyleName', 'public', TypeInfo(string), AnyControl, Keeps,
    function(X: TControl): string begin Result := X.StyleName end,
    procedure(X: TControl; V: string) begin X.StyleName := V end);

  // TControl, protected
  AddStr('Caption', 'protected', TypeInfo(TCaption), AnyControl, ByMessage,
    function(X: TControl): string begin Result := C(X).Caption end,
    procedure(X: TControl; V: string) begin C(X).Caption := V end);
  AddStr('Text', 'protected', TypeInfo(TCaption), AnyControl, ByMessage,
    function(X: TControl): string begin Result := C(X).Text end,
    procedure(X: TControl; V: string) begin C(X).Text := V end);
  AddOrd('Color', 'protected', TypeInfo(TColor), AnyControl,
    function(X: TControl): Integer begin Result := C(X).Color end,
    procedure(X: TControl; V: Integer) begin C(X).Color := V end);
  AddOrd('ParentColor', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).ParentColor) end,
    procedure(X: TControl; V: Integer) begin C(X).ParentColor := V <> 0 end);
  AddOrd('ParentFont', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).ParentFont) end,
    procedure(X: TControl; V: Integer) begin C(X).ParentFont := V <> 0 end);
  AddOrd('ParentShowHint', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).ParentShowHint) end,
    procedure(X: TControl; V: Integer) begin C(X).ParentShowHint := V <> 0 end);
  AddOrd('ParentBiDiMode', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).ParentBiDiMode) end,
    procedure(X: TControl; V: Integer) begin C(X).ParentBiDiMode := V <> 0 end);
  AddOrd('AutoSize', 'protected', TypeInfo(Boolean), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).AutoSize) end,
    procedure(X: TControl; V: Integer) begin C(X).AutoSize := V <> 0 end);
  AddOrd('DragMode', 'protected', TypeInfo(TDragMode), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).DragMode) end,
    procedure(X: TControl; V: Integer) begin C(X).DragMode := TDragMode(V) end);
  AddOrd('DragKind', 'protected', TypeInfo(TDragKind), AnyControl,
    function(X: TControl): Integer begin Result := Ord(C(X).DragKind) end,
    procedure(X: TControl; V: Integer) begin C(X).DragKind := TDragKind(V) end);
  AddOrd('DragCursor', 'protected', TypeInfo(TCursor), AnyControl,
    function(X: TControl): Integer begin Result := C(X).DragCursor end,
    procedure(X: TControl; V: Integer) begin C(X).DragCursor := V end);

  // TWinControl, public
  AddOrd('TabOrder', 'public', TypeInfo(TTabOrder), WinControl,
    function(X: TControl): Integer begin Result := W(X).TabOrder end,
    procedure(X: TControl; V: Integer) begin W(X).TabOrder := V end);
  AddOrd('TabStop', 'public', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).TabStop) end,
    procedure(X: TControl; V: Integer) begin W(X).TabStop := V <> 0 end);
  AddOrd('DoubleBuffered', 'public', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).DoubleBuffered) end,
    procedure(X: TControl; V: Integer) begin W(X).DoubleBuffered := V <> 0 end);
  AddOrd('ParentDoubleBuffered', 'public', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).ParentDoubleBuffered) end,
    procedure(X: TControl; V: Integer) begin W(X).ParentDoubleBuffered := V <> 0 end);
  AddOrd('Showing', 'public', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).Showing) end,
    nil);

  // TWinControl, protected
  AddOrd('BevelEdges', 'protected', TypeInfo(TBevelEdges), WinControl,
    function(X: TControl): Integer begin Result := Byte(W(X).BevelEdges) end,
    procedure(X: TControl; V: Integer) begin W(X).BevelEdges := TBevelEdges(Byte(V)) end);
  AddOrd('BevelInner', 'protected', TypeInfo(TBevelCut), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).BevelInner) end,
    procedure(X: TControl; V: Integer) begin W(X).BevelInner := TBevelCut(V) end);
  AddOrd('BevelOuter', 'protected', TypeInfo(TBevelCut), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).BevelOuter) end,
    procedure(X: TControl; V: Integer) begin W(X).BevelOuter := TBevelCut(V) end);
  AddOrd('BevelKind', 'protected', TypeInfo(TBevelKind), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).BevelKind) end,
    procedure(X: TControl; V: Integer) begin W(X).BevelKind := TBevelKind(V) end);
  AddOrd('BevelWidth', 'protected', TypeInfo(TBevelWidth), WinControl,
    function(X: TControl): Integer begin Result := W(X).BevelWidth end,
    procedure(X: TControl; V: Integer) begin W(X).BevelWidth := V end);
  AddOrd('BorderWidth', 'protected', TypeInfo(TBorderWidth), WinControl,
    function(X: TControl): Integer begin Result := W(X).BorderWidth end,
    procedure(X: TControl; V: Integer) begin W(X).BorderWidth := V end);
  AddOrd('Ctl3D', 'protected', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).Ctl3D) end,
    procedure(X: TControl; V: Integer) begin W(X).Ctl3D := V <> 0 end);
  AddOrd('ParentCtl3D', 'protected', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).ParentCtl3D) end,
    procedure(X: TControl; V: Integer) begin W(X).ParentCtl3D := V <> 0 end);
  AddOrd('ParentBackground', 'protected', TypeInfo(Boolean), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).ParentBackground) end,
    procedure(X: TControl; V: Integer) begin W(X).ParentBackground := V <> 0 end);
  AddOrd('ImeMode', 'protected', TypeInfo(TImeMode), WinControl,
    function(X: TControl): Integer begin Result := Ord(W(X).ImeMode) end,
    procedure(X: TControl; V: Integer) begin W(X).ImeMode := TImeMode(V) end);
  AddStr('ImeName', 'protected', TypeInfo(TImeName), WinControl, Keeps,
    function(X: TControl): string begin Result := W(X).ImeName end,
    procedure(X: TControl; V: string) begin W(X).ImeName := V end);
end;

{ Names of integer values }

procedure RegisterNames;
var
  Names: TOrdNames;
begin
  Names := Default(TOrdNames);
  Names.ToText := function(V: Integer): string begin Result := ColorToString(TColor(V)) end;
  Names.FromText :=
    function(const S: string; out V: Integer): Boolean
    begin
      Result := IdentToColor(S, V) or TryStrToInt(S, V);
    end;
  Names.GetValues := procedure(Proc: TGetStrProc) begin GetColorValues(Proc) end;
  Names.Error := '"%s" is not a color. Use a name such as clRed or clBtnFace, or a number such as ' +
    '$00FF8000 ($00BBGGRR).';
  RegisterOrdNames('TColor', Names);

  Names := Default(TOrdNames);
  Names.ToText := function(V: Integer): string begin Result := CursorToString(TCursor(V)) end;
  Names.FromText :=
    function(const S: string; out V: Integer): Boolean
    begin
      Result := IdentToCursor(S, V) or TryStrToInt(S, V);
    end;
  Names.GetValues := procedure(Proc: TGetStrProc) begin GetCursorValues(Proc) end;
  Names.Error := '"%s" is not a cursor. Use a name such as crHandPoint, or a number.';
  RegisterOrdNames('TCursor', Names);

  Names := Default(TOrdNames);
  Names.ToText := function(V: Integer): string begin Result := ShortCutToText(TShortCut(V)) end;
  Names.FromText :=
    function(const S: string; out V: Integer): Boolean
    begin
      V := TextToShortCut(S);
      Result := (V <> 0) or (S = '') or TryStrToInt(S, V);
    end;
  Names.Error := '"%s" is not a shortcut. Use text such as Ctrl+S, or nothing for none.';
  RegisterOrdNames('TShortCut', Names);
end;

{ Objects }

procedure RegisterObjects;
begin
  // Tree nodes by their absolute index: parents before their children
  RegisterItemList('TListItems',
    function(List: TObject): Integer begin Result := TListItems(List).Count end,
    function(List: TObject; Index: Integer): TObject begin Result := TListItems(List).Item[Index] end);
  RegisterItemList('TTreeNodes',
    function(List: TObject): Integer begin Result := TTreeNodes(List).Count end,
    function(List: TObject; Index: Integer): TObject begin Result := TTreeNodes(List).Item[Index] end);

  // Reading TPicture.Bitmap turns a picture of another kind (the PNG of a
  // TImage) into a bitmap
  RegisterSkippedProperty('TPicture', 'Bitmap');
  RegisterSkippedProperty('TPicture', 'Icon');
  RegisterSkippedProperty('TPicture', 'Metafile');
  RegisterSkippedProperty('TPicture', 'WICImage');

  RegisterSummary('TFont',
    function(Obj: TObject): string
    begin
      Result := Format('(%s) %s, %d pt, %s', [Obj.ClassName, TFont(Obj).Name, TFont(Obj).Size,
        ColorToString(TFont(Obj).Color)]);
    end);
  RegisterSummary('TListItems',
    function(Obj: TObject): string
    begin
      Result := Format('(%s, Count = %d)', [Obj.ClassName, TListItems(Obj).Count]);
    end);
  RegisterSummary('TTreeNodes',
    function(Obj: TObject): string
    begin
      Result := Format('(%s, Count = %d)', [Obj.ClassName, TTreeNodes(Obj).Count]);
    end);
  RegisterSummary('TListItem',
    function(Obj: TObject): string
    begin
      Result := Format('(%s) %s', [Obj.ClassName, Shorten(TListItem(Obj).Caption)]);
    end);
  RegisterSummary('TTreeNode',
    function(Obj: TObject): string
    begin
      Result := Format('(%s) %s', [Obj.ClassName, Shorten(TTreeNode(Obj).Text)]);
    end);
end;

initialization
  RegisterExtraProps;
  RegisterNames;
  RegisterObjects;
end.
