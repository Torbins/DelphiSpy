unit TestMain;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Actions, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.ActnList, TestFrame;

type
  TfrmTest = class(TForm)
    btnOk: TButton;
    pnlLabelHost: TPanel;
    lblInfo: TLabel;
    edtDisabled: TEdit;
    pnlHost: TPanel;
    fraSample: TfraSample;
    cmbChoice: TComboBox;
    btnAction: TButton;
    alMain: TActionList;
    actSave: TAction;
    edtLabeled: TLabeledEdit;
    sbMain: TStatusBar;
    lvItems: TListView;
    tvItems: TTreeView;
    pnlImageHost: TPanel;
    imgIcon: TImage;
    procedure FormCreate(Sender: TObject);
    procedure btnOkClick(Sender: TObject);
    procedure actSaveExecute(Sender: TObject);
  end;

var
  frmTest: TfrmTest;

implementation

{$R *.dfm}

procedure TfrmTest.FormCreate(Sender: TObject);
const
  Bitness = {$IFDEF WIN64}'x64'{$ELSE}'x86'{$ENDIF};
var
  Linking: string;
  Item: TListItem;
begin
  // The test script finds each variant by this caption
  if FindClassHInstance(TForm) <> HInstance then
    Linking := 'packages'
  else
    Linking := 'static';
{$IFDEF SHAREMEM}
  Linking := Linking + ' ShareMem';
{$ENDIF}
{$IFDEF SIMPLESHAREMEM}
  Linking := Linking + ' SimpleShareMem';
{$ENDIF}
{$IFDEF DELPHISPY_SERVER}
  Linking := Linking + ' server';
{$ENDIF}
  Caption := Format('DelphiSpy Test %d %s %s', [Trunc(CompilerVersion), Bitness, Linking]);

  // The DFM keeps these items in binary form
  Item := lvItems.Items.Add;
  Item.Caption := 'First';
  Item.SubItems.Add('One');
  Item := lvItems.Items.Add;
  Item.Caption := 'Second';
  Item.SubItems.Add('Two');
  tvItems.Items.AddChild(tvItems.Items.Add(nil, 'Root'), 'Child');
  tvItems.Items.Add(nil, 'Other');
  // Reading Picture.Bitmap would turn it into a bitmap
  imgIcon.Picture.Assign(Application.Icon);
end;

procedure TfrmTest.btnOkClick(Sender: TObject);
begin
  Tag := Tag + 1;
end;

procedure TfrmTest.actSaveExecute(Sender: TObject);
begin
  Tag := Tag + 10;
end;

end.
