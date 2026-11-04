unit FmxTestFrame;

interface

uses
  System.Classes, FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Edit, FMX.Objects,
  FMX.Controls.Presentation;

type
  TfraFmxSample = class(TFrame)
    rctGoHost: TRectangle;
    sbtnGo: TSpeedButton;
    edtFrame: TEdit;
    procedure sbtnGoClick(Sender: TObject);
  end;

implementation

{$R *.fmx}

procedure TfraFmxSample.sbtnGoClick(Sender: TObject);
begin
  Tag := Tag + 1;
end;

end.
