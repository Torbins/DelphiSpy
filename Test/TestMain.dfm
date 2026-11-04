object frmTest: TfrmTest
  Left = 200
  Top = 200
  Caption = 'VclSpy Test'
  ClientHeight = 260
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poDesigned
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 15
  object btnOk: TButton
    Left = 16
    Top = 16
    Width = 100
    Height = 28
    Caption = 'OK'
    TabOrder = 0
    OnClick = btnOkClick
  end
  object pnlLabelHost: TPanel
    Left = 132
    Top = 16
    Width = 150
    Height = 28
    BevelOuter = bvNone
    Caption = 'LabelHost'
    TabOrder = 1
    object lblInfo: TLabel
      Left = 0
      Top = 0
      Width = 150
      Height = 28
      Align = alClient
      Caption = 'Info label'
    end
  end
  object edtDisabled: TEdit
    Left = 16
    Top = 60
    Width = 266
    Height = 23
    Enabled = False
    TabOrder = 2
    Text = 'Disabled edit'
  end
  object pnlHost: TPanel
    Left = 16
    Top = 96
    Width = 420
    Height = 100
    BevelOuter = bvLowered
    TabOrder = 3
    inline fraSample: TfraSample
      Left = 1
      Top = 1
      Width = 418
      Height = 98
      Align = alClient
      TabOrder = 0
    end
  end
  object cmbChoice: TComboBox
    Left = 16
    Top = 212
    Width = 200
    Height = 23
    TabOrder = 4
    Text = 'Choice'
    Items.Strings = (
      'One'
      'Two')
  end
  object btnAction: TButton
    Left = 232
    Top = 210
    Width = 100
    Height = 28
    Action = actSave
    TabOrder = 5
  end
  object alMain: TActionList
    Left = 384
    Top = 16
    object actSave: TAction
      Caption = 'Save'
      OnExecute = actSaveExecute
    end
  end
end
