unit TestMain;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Actions, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ActnList, TestFrame;

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
begin
  // The test script finds each variant by this caption
  if FindClassHInstance(TForm) <> HInstance then
    Linking := 'packages'
  else
    Linking := 'static';
  Caption := Format('VclSpy Test %d %s %s', [Trunc(CompilerVersion), Bitness, Linking]);
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
