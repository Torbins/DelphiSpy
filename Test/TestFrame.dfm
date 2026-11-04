object fraSample: TfraSample
  Left = 0
  Top = 0
  Width = 418
  Height = 98
  TabOrder = 0
  object pnlGoHost: TPanel
    Left = 8
    Top = 8
    Width = 120
    Height = 32
    BevelOuter = bvNone
    Caption = 'GoHost'
    TabOrder = 0
    object sbtnGo: TSpeedButton
      Left = 0
      Top = 0
      Width = 120
      Height = 32
      Align = alClient
      Caption = 'Go'
      OnClick = sbtnGoClick
    end
  end
  object edtFrame: TEdit
    Left = 140
    Top = 12
    Width = 200
    Height = 23
    TabOrder = 1
    Text = 'Frame edit'
  end
end
