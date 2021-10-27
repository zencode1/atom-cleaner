object Form2: TForm2
  Left = 0
  Top = 0
  Caption = 'Global Atom Cleaner'
  ClientHeight = 319
  ClientWidth = 755
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  PixelsPerInch = 96
  DesignSize = (
    755
    319)
  TextHeight = 15
  object InspectBtn: TButton
    Left = 8
    Top = 24
    Width = 75
    Height = 25
    Caption = 'Inspect'
    TabOrder = 0
    OnClick = InspectBtnClick
  end
  object CleanBtn: TButton
    Left = 89
    Top = 24
    Width = 75
    Height = 25
    Caption = 'Clean'
    TabOrder = 1
    OnClick = CleanBtnClick
  end
  object Memo1: TMemo
    Left = 8
    Top = 55
    Width = 739
    Height = 256
    Anchors = [akLeft, akTop, akRight, akBottom]
    ScrollBars = ssBoth
    TabOrder = 2
    ExplicitWidth = 608
  end
  object PidBtn: TButton
    Left = 320
    Top = 25
    Width = 99
    Height = 25
    Caption = 'Inspect Process'
    TabOrder = 3
    OnClick = PidBtnClick
  end
  object PidEdit: TLabeledEdit
    Left = 193
    Top = 26
    Width = 121
    Height = 23
    EditLabel.Width = 21
    EditLabel.Height = 15
    EditLabel.Caption = 'PID:'
    NumbersOnly = True
    TabOrder = 4
    Text = ''
  end
  object DeleteAtomBtn: TButton
    Left = 576
    Top = 24
    Width = 99
    Height = 25
    Caption = 'Delete Atom'
    TabOrder = 5
    OnClick = DeleteAtomBtnClick
  end
  object AtomEdit: TLabeledEdit
    Left = 449
    Top = 25
    Width = 121
    Height = 23
    EditLabel.Width = 95
    EditLabel.Height = 15
    EditLabel.Caption = 'Atom Index (hex):'
    TabOrder = 6
    Text = ''
  end
end
