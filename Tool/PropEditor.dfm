object frmPropEditor: TfrmPropEditor
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  Caption = 'Edit property'
  ClientHeight = 163
  ClientWidth = 470
  Color = clBtnFace
  Constraints.MinWidth = 360
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  ShowHint = True
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 470
    Height = 66
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblProperty: TLabel
      Left = 10
      Top = 8
      Width = 70
      Height = 15
      Caption = 'Property'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblError: TLabel
      Left = 10
      Top = 30
      Width = 450
      Height = 32
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clRed
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      WordWrap = True
    end
  end
  object pnlEditor: TPanel
    Left = 0
    Top = 66
    Width = 470
    Height = 31
    Align = alClient
    BevelOuter = bvNone
    Padding.Left = 10
    Padding.Top = 4
    Padding.Right = 10
    TabOrder = 1
    object edtValue: TEdit
      Left = 10
      Top = 4
      Width = 450
      Height = 23
      Align = alTop
      TabOrder = 0
    end
    object cmbValue: TComboBox
      Left = 10
      Top = 27
      Width = 450
      Height = 23
      Align = alTop
      DropDownCount = 20
      TabOrder = 1
    end
    object clbValue: TCheckListBox
      Left = 10
      Top = 50
      Width = 450
      Height = 0
      Align = alClient
      ItemHeight = 17
      TabOrder = 2
    end
    object memValue: TMemo
      Left = 10
      Top = 50
      Width = 450
      Height = 0
      Align = alClient
      ScrollBars = ssVertical
      TabOrder = 3
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 97
    Width = 470
    Height = 66
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    object lblNote: TLabel
      Left = 110
      Top = 8
      Width = 350
      Height = 15
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      EllipsisPosition = epEndEllipsis
    end
    object chkMultiLine: TCheckBox
      Left = 10
      Top = 7
      Width = 94
      Height = 17
      Caption = 'Multi-line'
      TabOrder = 0
      OnClick = chkMultiLineClick
    end
    object btnOk: TButton
      Left = 294
      Top = 32
      Width = 80
      Height = 25
      Anchors = [akRight, akBottom]
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 1
    end
    object btnCancel: TButton
      Left = 380
      Top = 32
      Width = 80
      Height = 25
      Anchors = [akRight, akBottom]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 2
    end
  end
end
