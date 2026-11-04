object frmTest: TfrmTest
  Left = 200
  Top = 200
  Caption = 'VclSpy Test'
  ClientHeight = 360
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
  object edtLabeled: TLabeledEdit
    Left = 300
    Top = 60
    Width = 140
    Height = 23
    EditLabel.Width = 42
    EditLabel.Height = 15
    EditLabel.Caption = 'Labeled'
    TabOrder = 6
    Text = 'Labeled edit'
  end
  object lvItems: TListView
    Left = 16
    Top = 248
    Width = 200
    Height = 84
    Columns = <
      item
        Caption = 'Name'
        Width = 90
      end
      item
        Caption = 'Value'
        Width = 90
      end>
    TabOrder = 7
    ViewStyle = vsReport
  end
  object tvItems: TTreeView
    Left = 232
    Top = 248
    Width = 204
    Height = 84
    Indent = 19
    TabOrder = 8
  end
  object pnlImageHost: TPanel
    Left = 300
    Top = 12
    Width = 40
    Height = 36
    BevelOuter = bvNone
    Caption = 'ImageHost'
    TabOrder = 9
    object imgIcon: TImage
      Left = 0
      Top = 0
      Width = 40
      Height = 36
      Align = alClient
    end
  end
  object sbMain: TStatusBar
    Left = 0
    Top = 341
    Width = 460
    Height = 19
    Panels = <
      item
        Text = 'Ready'
        Width = 120
      end
      item
        Text = 'Second'
        Width = 80
      end>
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
