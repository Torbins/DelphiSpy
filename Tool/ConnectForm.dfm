object frmConnect: TfrmConnect
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  Caption = 'Connect to an application over the network'
  ClientHeight = 330
  ClientWidth = 560
  Color = clBtnFace
  Constraints.MinHeight = 280
  Constraints.MinWidth = 440
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  ShowHint = True
  OnCloseQuery = FormCloseQuery
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 15
  object pnlSearch: TPanel
    Left = 0
    Top = 0
    Width = 560
    Height = 64
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblHosts: TLabel
      Left = 10
      Top = 8
      Width = 540
      Height = 15
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      Caption =
        'Applications that link VclSpy.Server. Computers to search (empt' +
        'y: the local network):'
    end
    object edtHosts: TEdit
      Left = 10
      Top = 29
      Width = 444
      Height = 23
      Hint =
        'Host names or IPv4 addresses, separated by ";". An address endin' +
        'g in .0 searches its /24 network.'
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 0
      TextHint = 'e.g. testpc;192.168.5.0'
    end
    object btnSearch: TButton
      Left = 460
      Top = 28
      Width = 90
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Search'
      TabOrder = 1
      OnClick = btnSearchClick
    end
  end
  object lvServers: TListView
    AlignWithMargins = True
    Left = 10
    Top = 64
    Width = 540
    Height = 168
    Margins.Left = 10
    Margins.Top = 0
    Margins.Right = 10
    Margins.Bottom = 0
    Align = alClient
    Columns = <
      item
        Caption = 'Application'
        Width = 360
      end
      item
        Caption = 'Address'
        Width = 150
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 1
    ViewStyle = vsReport
    OnDblClick = lvServersDblClick
    OnSelectItem = lvServersSelectItem
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 232
    Width = 560
    Height = 98
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    object lblPassword: TLabel
      Left = 10
      Top = 13
      Width = 50
      Height = 15
      Caption = 'Password'
    end
    object lblStatus: TLabel
      Left = 10
      Top = 40
      Width = 540
      Height = 15
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      EllipsisPosition = epEndEllipsis
    end
    object edtPassword: TEdit
      Left = 80
      Top = 10
      Width = 200
      Height = 23
      Hint = 'VclSpyServerPassword of the application, if it sets one'
      PasswordChar = '*'
      TabOrder = 0
    end
    object btnConnect: TButton
      Left = 374
      Top = 64
      Width = 85
      Height = 25
      Anchors = [akRight, akBottom]
      Caption = 'Connect'
      Default = True
      TabOrder = 1
      OnClick = btnConnectClick
    end
    object btnCancel: TButton
      Left = 465
      Top = 64
      Width = 85
      Height = 25
      Anchors = [akRight, akBottom]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 2
    end
  end
end
