unit Unit2;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Mask, Vcl.ExtCtrls;

type
  TForm2 = class(TForm)
    InspectBtn: TButton;
    CleanBtn: TButton;
    Memo1: TMemo;
    PidBtn: TButton;
    PidEdit: TLabeledEdit;
    DeleteAtomBtn: TButton;
    AtomEdit: TLabeledEdit;
    procedure CleanBtnClick(Sender: TObject);
    procedure DeleteAtomBtnClick(Sender: TObject);
    procedure InspectBtnClick(Sender: TObject);
    procedure PidBtnClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form2: TForm2;

implementation

{$R *.dfm}

uses
  Winapi.PsAPI;

// Copied from JclDebug and then modified
const
  THREAD_SUSPEND_RESUME    = $0002;
  THREAD_GET_CONTEXT       = $0008;
  THREAD_QUERY_INFORMATION = $0040;
function OpenThread(DesiredAccess: DWORD; InheritHandle: BOOL; ThreadID: DWORD): THandle;
type
  TOpenThreadFunc = function(DesiredAccess: DWORD; InheritHandle: BOOL; ThreadID: DWORD): THandle; stdcall;
var
  Kernel32Lib: THandle;
  OpenThreadFunc: TOpenThreadFunc;
begin
  Result := 0;
  Kernel32Lib := GetModuleHandle(kernel32);
  if Kernel32Lib <> 0 then
  begin
    // OpenThread only exists since Windows ME
    OpenThreadFunc := GetProcAddress(Kernel32Lib, 'OpenThread');
    if Assigned(OpenThreadFunc) then
      Result := OpenThreadFunc(DesiredAccess, InheritHandle, ThreadID);
  end;
end;

function DeleteAtom(AtomNdx : ATOM) : Boolean;
begin
  SetLastError(ERROR_SUCCESS);
  GlobalDeleteAtom(AtomNdx);
  Result := GetLastError = ERROR_SUCCESS;
end;

function GarbageCollectAtoms(Logs: TStrings; Clean: Boolean) : Integer;
type
  ActiveResult = ( No, Yes, Denied );

var
  atomNdx : ATOM;
  charBuffer : Array [0 .. 4096] of Char; // reusable
  countDelphiProcs,
  countActiveProcs,
  countRemovedProcs,
  countCantRemoveProcs,
  countUsedAtoms,
  countScannedAtoms,
  countUnknownProcs : Integer;

  function GetProcessIdFromAtomName(AtomName : string; var ThreadId, ProcId : Cardinal) : ActiveResult;
  var
    i64 : Int64;
    len : Integer;
    procStr : string;
    threadHandle : THandle;

  begin
    Result := ActiveResult.Yes;
    i64 := 0;
    ThreadId := 0;
    ProcId := 0;

    // Note: either the original code we used was buggy or Embarcadero changed the format of
    // 'ControlOfs' and 'WndProcPtr'.  Look at Controls.pas and you will find that the string
    // is followed by 8 digits for HInstance and 8 digits for ThreadID.
    len := Length(AtomName);
    if (Pos('ControlOfs', AtomName) = 1) or
       (Pos('WndProcPtr', AtomName) = 1) then begin
      // The last 8 digits are the thread id
      procStr := Copy(AtomName, len - 7, 8);
      if TryStrToInt64('$' + Copy(procStr, Length(procStr) - 7, 8), i64) then begin
        ThreadId := i64;
        threadHandle := OpenThread(THREAD_QUERY_INFORMATION, false, i64);
        if threadHandle <> 0 then begin
          ProcId := GetProcessIdOfThread(threadHandle);
          CloseHandle(threadHandle);
        end else if GetLastError = ERROR_ACCESS_DENIED then
          Result := ActiveResult.Denied; // access is denied to open the thread
      end else
        Result := ActiveResult.No; // not numeric, not a Delphi atom
    end else
    if (Pos('Delphi', AtomName) = 1) or
       (Pos('DlgInstancePtr', AtomName) = 1) or
       (Pos('FIREMONKEY', AtomName) = 1) then begin
      // The last 8 digits are the process id
      if TryStrToInt64('$' + Copy(AtomName, len - 7, 8), i64) then
        ProcId := i64
      else
        Result := ActiveResult.No; // not numeric, not a Delphi atom
    end else
      Result := ActiveResult.No;
  end;

  function IsProcessIdActive(ProcessId : Cardinal; var ProcName : string) : ActiveResult;
  var
    len : Integer;
    handleProc : THandle;

  begin
    handleProc := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, ProcessId);
    if handleProc <> 0 then begin
      Result := ActiveResult.Yes;
      if Assigned(Logs) then begin
        // only need the process name if logging
        len := GetModuleFileNameEx(handleProc, 0, charBuffer, Length(charBuffer) - 1);
        ProcName := Copy(charBuffer, 0, len);
      end;
      CloseHandle(handleProc);
    end else begin
      if GetLastError = ERROR_ACCESS_DENIED then
        Result := ActiveResult.Denied
      else
        Result := ActiveResult.No;
    end;
  end;

  procedure Log(const msg : string);
  begin
    if Assigned(Logs) then
      Logs.Add(msg);
  end;

  procedure InspectAtom(AtomNdx : ATOM);
  var
    len : Integer;
    atomName, procName, msg : string;
    procId, threadId : Cardinal;
    isActive : ActiveResult;

  begin
    len := GlobalGetAtomName(atomNdx, charBuffer, Length(charBuffer) - 1);
    if len = 0 then
      Exit;
    Inc(countUsedAtoms);
    atomName := Copy(charBuffer, 0, len);
    isActive := GetProcessIdFromAtomName(atomName, threadId, procId);
    if isActive = ActiveResult.No then
      Exit;

    Inc(countDelphiProcs);

    msg := 'Atom#: ' + IntToHex(atomNdx, 4) + ' AtomName: ' + atomName;
    if threadId <> 0 then
      msg := msg + ' ThreadID: ' + IntToStr(threadId);
    msg := msg + ' ProcID: ' + IntToStr(procId);
    Log(msg);

    if isActive <> ActiveResult.Denied then
      isActive := IsProcessIdActive(procId, procName);

    case isActive of
      ActiveResult.Denied: // could not get information about process
      begin
        Inc(countUnknownProcs);
        if Clean then
          Log('- Could not get information about the process and the Atom will not be removed!')
        else
          Log('- Could not get information about the process')
      end;

      ActiveResult.No: // process is not active
      begin
        // remove atom from atom table
        if not Clean then begin
          // the atom would be removed
          Inc(countRemovedProcs);
          Log('- LEAK! ProcID is not active anymore!');
        end else if DeleteAtom(atomNdx) then begin
          // the atom was removed
          Inc(countRemovedProcs);
          Log('- LEAK! Atom was removed from Global Atom Table because ProcID is not active anymore!')
        end else begin
          // the atom could not be removed
          Inc(countCantRemoveProcs);
          Log('- Atom was not removed from Global Atom Table because function "GlobalDeleteAtom" has failed! Reason: ' + SysErrorMessage(GetLastError));
        end;
      end;

      ActiveResult.Yes: // process is active
      begin
        Inc(countActiveProcs);
        Log('- Process is active! Program: ' + procName);
      end;
    end;
  end;

begin
  // initialize the counters
  countDelphiProcs := 0;
  countActiveProcs := 0;
  countRemovedProcs := 0;
  countUnknownProcs := 0;
  countCantRemoveProcs := 0;
  countUsedAtoms := 0;
  countScannedAtoms := 0;

  Log('Scanning Global Atom Table...');

  for atomNdx := $C000 to $FFFF do begin
    Inc(countScannedAtoms);
    InspectAtom(atomNdx);
  end;

  Log('');
  Log('Scan complete:');
  Log('- Atoms scanned: ' + IntToStr(countScannedAtoms));
  Log('- Atoms in use: ' + IntToStr(countUsedAtoms));
  Log('- Delphi Processes: ' + IntToStr(countDelphiProcs));
  Log('  - Active: ' + IntToStr(countActiveProcs));
  if Clean then
    Log('  - Removed: ' + IntToStr(countRemovedProcs))
  else
    Log('  - Can remove: ' + IntToStr(countRemovedProcs));
  Log('  - Not removed: ' + IntToStr(countCantRemoveProcs));
  Log('  - Unknown: ' + IntToStr(countUnknownProcs));

  Result := countRemovedProcs;
end;

procedure TForm2.CleanBtnClick(Sender: TObject);
begin
  if Memo1.Lines.Count > 0 then
    Memo1.Lines.Add(EmptyStr);

  GarbageCollectAtoms(Memo1.Lines, True);
end;

procedure TForm2.DeleteAtomBtnClick(Sender: TObject);
var
  atomNdx : ATOM;

begin
  if Memo1.Lines.Count > 0 then
    Memo1.Lines.Add(EmptyStr);

  atomNdx := StrToInt('$' + Trim(AtomEdit.Text));
  if atomNdx < $C000 then begin
    Memo1.Lines.Add('Atom index is out of range');
    Exit;
  end;

  Memo1.Lines.Add('Manually deleting atom ' + IntToHex(atomNdx, 4) + ' I hope you meant to do this');
  if DeleteAtom(atomNdx) then
    Memo1.Lines.Add('Success')
  else
    Memo1.Lines.Add('Failed: ' + SysErrorMessage(GetLastError));
end;

procedure TForm2.InspectBtnClick(Sender: TObject);
begin
  if Memo1.Lines.Count > 0 then
    Memo1.Lines.Add(EmptyStr);

  GarbageCollectAtoms(Memo1.Lines, False);
end;

procedure TForm2.PidBtnClick(Sender: TObject);
var
  len : Integer;
  handleProc : THandle;
  procName : string;
  charBuffer : Array [0..2048] of Char;
  code : DWORD;
  pid : Cardinal;

begin
  if Memo1.Lines.Count > 0 then
    Memo1.Lines.Add(EmptyStr);

  pid := StrToInt(Trim(PidEdit.Text));
  Memo1.Lines.Add('Opening pid: ' + IntToStr(pid));
  handleProc := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, pid);
  if handleProc = 0 then begin
    Memo1.Lines.Add('Error: ' + SysErrorMessage(GetLastError));
    Exit;
  end;
  Memo1.Lines.Add('Opened');
  GetExitCodeProcess(handleProc, code);
  Memo1.Lines.Add('Exit Code: ' + IntToStr(code));
  len := GetModuleFileNameEx(handleProc, 0, charBuffer, Length(charBuffer) - 1);
  procName := Copy(charBuffer, 0, len);
  Memo1.Lines.Add('Name: ' + procName);
  CloseHandle(handleProc);
end;

end.
