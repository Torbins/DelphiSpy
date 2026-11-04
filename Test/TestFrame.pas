unit TestFrame;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons;

type
  TfraSample = class(TFrame)
    pnlGoHost: TPanel;
    sbtnGo: TSpeedButton;
    edtFrame: TEdit;
    procedure sbtnGoClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TfraSample.sbtnGoClick(Sender: TObject);
begin
  Tag := Tag + 1;
end;

end.
