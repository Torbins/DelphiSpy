object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'VclSpy - Delphi VCL control inspector'
  ClientHeight = 640
  ClientWidth = 760
  Color = clBtnFace
  Constraints.MinHeight = 480
  Constraints.MinWidth = 600
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  ShowHint = True
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 760
    Height = 60
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblHint: TLabel
      Left = 64
      Top = 10
      Width = 420
      Height = 15
      Caption =
        'Drag the finder onto a control in a Delphi VCL application built' +
        ' with runtime packages.'
    end
    object lblTarget: TLabel
      Left = 64
      Top = 34
      Width = 480
      Height = 15
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      EllipsisPosition = epEndEllipsis
    end
    object pnlFinder: TPanel
      Left = 10
      Top = 8
      Width = 44
      Height = 44
      BevelOuter = bvLowered
      TabOrder = 0
    end
    object chkStayOnTop: TCheckBox
      Left = 560
      Top = 8
      Width = 190
      Height = 17
      Anchors = [akTop, akRight]
      Caption = 'Stay on top'
      TabOrder = 1
      OnClick = chkStayOnTopClick
    end
    object btnCopyName: TButton
      Left = 560
      Top = 29
      Width = 92
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Copy name'
      TabOrder = 2
      OnClick = btnCopyNameClick
    end
    object btnCopyJson: TButton
      Left = 658
      Top = 29
      Width = 92
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Copy JSON'
      TabOrder = 3
      OnClick = btnCopyJsonClick
    end
  end
  object pnlSummary: TPanel
    Left = 0
    Top = 60
    Width = 760
    Height = 232
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 1
    object lblName: TLabel
      Left = 10
      Top = 11
      Width = 35
      Height = 15
      Caption = 'Name'
    end
    object lblClass: TLabel
      Left = 10
      Top = 44
      Width = 27
      Height = 15
      Caption = 'Class'
    end
    object lblUnit: TLabel
      Left = 10
      Top = 71
      Width = 22
      Height = 15
      Caption = 'Unit'
    end
    object lblForm: TLabel
      Left = 10
      Top = 98
      Width = 28
      Height = 15
      Caption = 'Form'
    end
    object lblPath: TLabel
      Left = 10
      Top = 125
      Width = 66
      Height = 15
      Caption = 'Owner path'
    end
    object lblParents: TLabel
      Left = 10
      Top = 152
      Width = 70
      Height = 15
      Caption = 'Parent path'
    end
    object lblModule: TLabel
      Left = 10
      Top = 179
      Width = 42
      Height = 15
      Caption = 'Module'
    end
    object lblText: TLabel
      Left = 10
      Top = 206
      Width = 22
      Height = 15
      Caption = 'Text'
    end
    object edtName: TEdit
      Left = 96
      Top = 6
      Width = 654
      Height = 25
      Anchors = [akLeft, akTop, akRight]
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -15
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      ReadOnly = True
      TabOrder = 0
    end
    object edtClass: TEdit
      Left = 96
      Top = 40
      Width = 654
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      ReadOnly = True
      TabOrder = 1
    end
    object edtUnit: TEdit
      Left = 96
      Top = 67
      Width = 654
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      ReadOnly = True
      TabOrder = 2
    end
    object edtForm: TEdit
      Left = 96
      Top = 94
      Width = 654
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      ReadOnly = True
      TabOrder = 3
    end
    object edtPath: TEdit
      Left = 96
      Top = 121
      Width = 654
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      ReadOnly = True
      TabOrder = 4
    end
    object edtParents: TEdit
      Left = 96
      Top = 148
      Width = 654
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      ReadOnly = True
      TabOrder = 5
    end
    object edtModule: TEdit
      Left = 96
      Top = 175
      Width = 654
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      ReadOnly = True
      TabOrder = 6
    end
    object edtText: TEdit
      Left = 96
      Top = 202
      Width = 654
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      ReadOnly = True
      TabOrder = 7
    end
  end
  object pgcDetails: TPageControl
    Left = 0
    Top = 292
    Width = 760
    Height = 329
    ActivePage = tabProperties
    Align = alClient
    TabOrder = 2
    object tabProperties: TTabSheet
      Caption = 'Properties'
      object edtFilter: TEdit
        Left = 0
        Top = 0
        Width = 752
        Height = 23
        Align = alTop
        TabOrder = 0
        TextHint = 'Filter by property name or value'
        OnChange = edtFilterChange
      end
      object lvProperties: TListView
        Left = 0
        Top = 23
        Width = 752
        Height = 276
        Align = alClient
        Columns = <
          item
            Caption = 'Name'
            Width = 180
          end
          item
            Caption = 'Value'
            Width = 400
          end
          item
            Caption = 'Type'
            Width = 140
          end>
        ReadOnly = True
        RowSelect = True
        TabOrder = 1
        ViewStyle = vsReport
      end
    end
    object tabEvents: TTabSheet
      Caption = 'Events'
      object lvEvents: TListView
        Left = 0
        Top = 0
        Width = 752
        Height = 299
        Align = alClient
        Columns = <
          item
            Caption = 'Event'
            Width = 130
          end
          item
            Caption = 'Handler'
            Width = 220
          end
          item
            Caption = 'Unit'
            Width = 110
          end
          item
            Caption = 'Instance'
            Width = 150
          end
          item
            Caption = 'Address'
            Width = 80
          end
          item
            Caption = 'Module'
            Width = 110
          end>
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
      end
    end
    object tabHierarchy: TTabSheet
      Caption = 'Hierarchy'
      object tvHierarchy: TTreeView
        Left = 0
        Top = 0
        Width = 752
        Height = 299
        Align = alClient
        Indent = 19
        ReadOnly = True
        TabOrder = 0
      end
    end
    object tabJson: TTabSheet
      Caption = 'JSON'
      object memJson: TMemo
        Left = 0
        Top = 0
        Width = 752
        Height = 299
        Align = alClient
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Consolas'
        Font.Style = []
        ParentFont = False
        ReadOnly = True
        ScrollBars = ssBoth
        TabOrder = 0
        WordWrap = False
      end
    end
    object tabHistory: TTabSheet
      Caption = 'History'
      object lbHistory: TListBox
        Left = 0
        Top = 0
        Width = 752
        Height = 299
        Align = alClient
        ItemHeight = 15
        TabOrder = 0
        OnClick = lbHistoryClick
      end
    end
  end
  object sbStatus: TStatusBar
    Left = 0
    Top = 621
    Width = 760
    Height = 19
    Panels = <>
    SimplePanel = True
  end
  object tmrFlash: TTimer
    Enabled = False
    Interval = 1500
    OnTimer = tmrFlashTimer
    Left = 704
    Top = 540
  end
end
