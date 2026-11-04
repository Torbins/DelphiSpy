unit PropEditor;

{ Edits one property value of the inspected control. The editor depends on
  the property's kind: a drop-down list for enumerations and Booleans, a
  combo box with names for colors and cursors, a check list for sets, and an
  edit box (or a memo, for multi-line text) for the rest. The text it returns
  goes to the inspector, which parses it for the property's type. }

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.JSON, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.CheckLst, Vcl.Graphics;

type
  TPropEditInfo = record
    Name, TypeName, Kind, Scope, Value: string;
    Values: TJSONArray; // names the type accepts, or nil
    Truncated: Boolean;
  end;

  TfrmPropEditor = class(TForm)
    pnlTop: TPanel;
    lblProperty: TLabel;
    lblError: TLabel;
    pnlEditor: TPanel;
    edtValue: TEdit;
    cmbValue: TComboBox;
    clbValue: TCheckListBox;
    memValue: TMemo;
    pnlBottom: TPanel;
    chkMultiLine: TCheckBox;
    lblNote: TLabel;
    btnOk: TButton;
    btnCancel: TButton;
    procedure chkMultiLineClick(Sender: TObject);
  private
    FTall: Boolean;
    procedure Setup(const Info: TPropEditInfo; const Text, Error: string);
    function GetText: string;
    procedure ShowEditor(Editor: TWinControl);
  end;

// Shows the editor, starting with Text. Error, if not empty, is shown above
// it (the previous attempt failed). Returns True and the new text on OK.
function EditProperty(Owner: TCustomForm; const Info: TPropEditInfo; var Text: string;
  const Error: string): Boolean;

implementation

{$R *.dfm}

const
  TallEditorExtra = 160; // at 96 dpi; a check list or memo needs room

function EditProperty(Owner: TCustomForm; const Info: TPropEditInfo; var Text: string;
  const Error: string): Boolean;
var
  Dialog: TfrmPropEditor;
begin
  Dialog := TfrmPropEditor.Create(Owner);
  try
    Dialog.PopupMode := pmExplicit;
    Dialog.PopupParent := Owner; // stays above a "stay on top" DelphiSpy
    Dialog.Setup(Info, Text, Error);
    Result := Dialog.ShowModal = mrOk;
    if Result then
      Text := Dialog.GetText;
  finally
    Dialog.Free;
  end;
end;

function HasLineBreak(const S: string): Boolean;
begin
  Result := (Pos(#10, S) > 0) or (Pos(#13, S) > 0);
end;

{ TfrmPropEditor }

procedure TfrmPropEditor.Setup(const Info: TPropEditInfo; const Text, Error: string);
var
  Element: TJSONValue;
  Names: TStringList;
  I: Integer;
begin
  Caption := 'Edit ' + Info.Name;
  lblProperty.Caption := Format('%s: %s   (%s)', [Info.Name, Info.TypeName, Info.Scope]);
  lblError.Caption := Error;
  lblError.Hint := Error;
  lblError.Visible := Error <> '';
  if Error = '' then
  begin
    Height := Height - (pnlTop.Height - lblError.Top);
    pnlTop.Height := lblError.Top;
  end;
  chkMultiLine.Visible := Info.Kind = 'string';
  if not chkMultiLine.Visible then
    lblNote.SetBounds(chkMultiLine.Left, lblNote.Top, lblNote.BoundsRect.Right - chkMultiLine.Left,
      lblNote.Height);
  lblNote.Caption := '';

  if Info.Kind = 'set' then
  begin
    ShowEditor(clbValue);
    Names := TStringList.Create;
    try
      // "[akLeft,akTop]"
      Names.CommaText := StringReplace(StringReplace(Text, '[', '', []), ']', '', []);
      if Info.Values <> nil then
        for Element in Info.Values do
        begin
          I := clbValue.Items.Add(Element.Value);
          clbValue.Checked[I] := Names.IndexOf(Element.Value) >= 0;
        end;
    finally
      Names.Free;
    end;
  end
  else if (Info.Kind = 'enum') and (Info.Values <> nil) then
  begin
    ShowEditor(cmbValue);
    cmbValue.Style := csDropDownList;
    for Element in Info.Values do
      cmbValue.Items.Add(Element.Value);
    cmbValue.ItemIndex := cmbValue.Items.IndexOf(Text);
  end
  else if Info.Values <> nil then
  begin
    // Colors and cursors: a name from the list, or a number
    ShowEditor(cmbValue);
    cmbValue.Style := csDropDown;
    for Element in Info.Values do
      cmbValue.Items.Add(Element.Value);
    cmbValue.Text := Text;
    if Info.TypeName = 'TColor' then
      lblNote.Caption := 'A name, or a number such as $00FF8000 ($00BBGGRR).'
    else
      lblNote.Caption := 'A name, or a number.';
  end
  else if Info.Kind = 'string' then
  begin
    chkMultiLine.Checked := HasLineBreak(Text); // shows the memo or the edit box
    chkMultiLineClick(nil);
    edtValue.Text := Text;
    memValue.Text := Text;
  end
  else
  begin
    ShowEditor(edtValue);
    edtValue.Text := Text;
    if Info.Kind = 'char' then
      lblNote.Caption := 'One character, or #code.';
  end;

  if Info.Truncated then
  begin
    lblNote.Caption := 'DelphiSpy only read the first characters of this value. OK replaces all of it.';
    lblNote.Font.Color := clRed;
  end;
  lblNote.Hint := lblNote.Caption;
end;

procedure TfrmPropEditor.ShowEditor(Editor: TWinControl);
begin
  // Once tall, the dialog stays tall when Multi-line is switched off again
  if ((Editor = clbValue) or (Editor = memValue)) and not FTall then
  begin
    Height := Height + MulDiv(TallEditorExtra, CurrentPPI, 96);
    FTall := True;
  end;
  edtValue.Visible := Editor = edtValue;
  cmbValue.Visible := Editor = cmbValue;
  clbValue.Visible := Editor = clbValue;
  memValue.Visible := Editor = memValue;
  ActiveControl := Editor;
end;

procedure TfrmPropEditor.chkMultiLineClick(Sender: TObject);
begin
  if chkMultiLine.Checked then
  begin
    if Sender <> nil then
      memValue.Text := edtValue.Text;
    ShowEditor(memValue);
    btnOk.Default := False; // Enter starts a new line
  end
  else
  begin
    if Sender <> nil then
      edtValue.Text := StringReplace(memValue.Text, sLineBreak, ' ', [rfReplaceAll]);
    ShowEditor(edtValue);
    btnOk.Default := True;
  end;
end;

function TfrmPropEditor.GetText: string;
var
  I: Integer;
begin
  if clbValue.Visible then
  begin
    Result := '';
    for I := 0 to clbValue.Items.Count - 1 do
      if clbValue.Checked[I] then
      begin
        if Result <> '' then
          Result := Result + ',';
        Result := Result + clbValue.Items[I];
      end;
    Result := '[' + Result + ']';
  end
  else if cmbValue.Visible then
    Result := cmbValue.Text
  else if memValue.Visible then
    Result := memValue.Text
  else
    Result := edtValue.Text;
end;

end.
