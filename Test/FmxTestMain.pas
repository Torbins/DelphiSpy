unit FmxTestMain;

interface

uses
  System.SysUtils, System.Classes, System.Actions, FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls,
  FMX.Edit, FMX.Layouts, FMX.ListBox, FMX.Objects, FMX.ActnList, FMX.Controls.Presentation, FmxTestFrame;

type
  TfrmFmxTest = class(TForm)
    btnOk: TButton;
    lblInfo: TLabel;
    edtDisabled: TEdit;
    lytHost: TLayout;
    cmbChoice: TComboBox;
    btnAction: TButton;
    alMain: TActionList;
    actSave: TAction;
    rctColor: TRectangle;
    lstItems: TListBox;
    procedure FormCreate(Sender: TObject);
    procedure btnOkClick(Sender: TObject);
    procedure actSaveExecute(Sender: TObject);
  public
    fraSample: TfraFmxSample;
  end;

var
  frmFmxTest: TfrmFmxTest;

implementation

{$R *.fmx}

procedure TfrmFmxTest.FormCreate(Sender: TObject);
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
{$IFDEF SHAREMEM}
  Linking := Linking + ' ShareMem';
{$ENDIF}
{$IFDEF SIMPLESHAREMEM}
  Linking := Linking + ' SimpleShareMem';
{$ENDIF}
{$IFDEF VCLSPY_SERVER}
  Linking := Linking + ' server';
{$ENDIF}
  Caption := Format('VclSpy FMX Test %d %s %s', [Trunc(CompilerVersion), Bitness, Linking]);

  fraSample := TfraFmxSample.Create(Self);
  fraSample.Name := 'fraSample';
  fraSample.Parent := lytHost;
  fraSample.Align := TAlignLayout.Client;

  cmbChoice.Items.Add('One');
  cmbChoice.Items.Add('Two');
  cmbChoice.ItemIndex := 0;
  lstItems.Items.Add('First');
  lstItems.Items.Add('Second');
end;

procedure TfrmFmxTest.btnOkClick(Sender: TObject);
begin
  Tag := Tag + 1;
end;

procedure TfrmFmxTest.actSaveExecute(Sender: TObject);
begin
  Tag := Tag + 10;
end;

end.
