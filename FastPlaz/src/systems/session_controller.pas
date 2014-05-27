unit session_controller;

{$mode objfpc}{$H+}

interface

uses
  fpcgi, md5, IniFiles,
  Classes, SysUtils;

const
  MaxIniCreate = 5;
  _SESSION_SESSION = 'session';
  _SESSION_DATA = 'data';

  _SESSION_ACTIVE = 'active';         // Start time of session
  _SESSION_KEYSTART = 'start';         // Start time of session
  _SESSION_KEYLAST = 'last';          // Last seen time of session
  _SESSION_KEYTIMEOUT = 'timeout';       // Timeout in seconds;
  _SESSION_TIMEOUT_DEFAULT = 3600;
  TDateTimeEpsilon = 2.2204460493e-16;

type

  { TSessionController }

  TSessionController = class(TObject)
  private
    FIniFile: TMemInifile;
    FSessionTimeout: integer;
    FSessionStarted, FSessionTerminated, FCached: boolean;
    FSessionPrefix, FSessionSuffix, FSessionExtension, FHttpCookie,
    FCookieID, FSessionID: string;
    FSessionDir: string;
    function GenerateSesionID: string;
    function CreateIniFile(const FileName: string): TMemIniFile;
    procedure DeleteIniFile;
    function GetIsExpired: boolean;
    function GetValue( variable: string): string;
    procedure SetValue( variable: string; AValue: string);
    procedure UpdateIniFile;

  public
    constructor Create();
    destructor Destroy; override;
    property Values[ variable: string]: string read GetValue write SetValue; default;
    property CookieID: string read FCookieID;
    property SessionID: string read FSessionID;
    property SessionDir: string read FSessionDir write FSessionDir;

    property IsExpired: boolean read GetIsExpired;

    function StartSession: boolean;
    procedure EndSession;
    procedure Terminate;

    function ReadDateTime(const variable:string):TDateTime;
    function ReadInteger(const variable:string):Integer;

    function _DateTimeDiff(const ANow, AThen: TDateTime): TDateTime;
  end;

implementation

{ TSessionController }

function TSessionController.GenerateSesionID: string;
begin
  Result := Application.EnvironmentVariable['REMOTE_ADDR'] + '-' +
    FCookieID + '-' + Application.EnvironmentVariable['HTTP_USER_AGENT'];
  Result := FSessionPrefix + MD5Print(MD5String(Result)) + '-' +
    FCookieID + FSessionSuffix;
end;

function TSessionController.CreateIniFile(const FileName: string): TMemIniFile;
var
  Count: integer;
begin
  Count := 0;
  Result := nil;
  repeat
    Inc(Count);
    try
      Result := TMemIniFile.Create(FileName, False);
    except
      On E: EFCreateError do
      begin
        if Count > MaxIniCreate then
          raise;
        Sleep(20);
      end;
      On E: EFOpenError do
      begin
        if Count > MaxIniCreate then
          raise;
        Sleep(20);
      end;
      On E: Exception do
        raise;
    end;
  until (Result <> nil);
end;

procedure TSessionController.DeleteIniFile;
begin
  try
    DeleteFile(FSessionDir + '/' + FSessionID + FSessionExtension);
  except
  end;
end;

function TSessionController.GetIsExpired: boolean;
var
  L: TDateTime;
  T: integer;
begin
  L:=FIniFile.ReadDateTime(_SESSION_SESSION,_SESSION_KEYLAST,0);
  T:=FIniFile.ReadInteger(_SESSION_SESSION,_SESSION_KEYTIMEOUT,FSessionTimeout);
  Result:=(((Now-L)+TDateTimeEpsilon)*SecsPerDay)>T;
  if Result then
    FIniFile.EraseSection(_SESSION_DATA);
end;

function TSessionController.GetValue( variable: string): string;
begin
  Result:='';
  if (not FSessionStarted)or(FSessionTerminated)or(FIniFile=nil) then Exit;
  Result:=FIniFile.ReadString(_SESSION_DATA,variable,'');
end;

procedure TSessionController.SetValue( variable: string; AValue: string);
begin
  if (not FSessionStarted)or(FSessionTerminated)or(FIniFile=nil) then Exit;
  try
    FIniFile.WriteString(_SESSION_DATA,variable,AValue);
  except
  end;
end;

procedure TSessionController.UpdateIniFile;
var
  Count: integer;
  OK: boolean;
begin
  Count := 0;
  OK := False;
  repeat
    Inc(Count);
    try
      TMemIniFile(FIniFile).UpdateFile;
      OK := True;
    except
      On E: EFCreateError do
      begin
        if Count > MaxIniCreate then
          raise;
        Sleep(20);
      end;
      On E: EFOpenError do
      begin
        if Count > MaxIniCreate then
          raise;
        Sleep(20);
      end;
      On E: Exception do
        raise;
    end;
  until OK;
end;

function TSessionController._DateTimeDiff(const ANow, AThen: TDateTime
  ): TDateTime;
begin
  Result:= ANow - AThen;
  if (ANow>0) and (AThen<0) then
    Result:=Result-0.5
  else if (ANow<-1.0) and (AThen>-1.0) then
    Result:=Result+0.5;
end;

constructor TSessionController.Create;
begin
  inherited Create();
  FHttpCookie := Application.EnvironmentVariable['HTTP_COOKIE'];
  FCookieID := Copy(FHttpCookie, Pos('__cfduid=', FHttpCookie) + 9,
    Length(FHttpCookie) - Pos('__cfduid=', FSessionID) - 9);
  FSessionID := GenerateSesionID();
  FSessionDir := Application.EnvironmentVariable['TEMP'];
  FSessionExtension := '';
  FSessionStarted := False;
  FSessionTerminated := False;
  FCached := False;
  FSessionTimeout := _SESSION_TIMEOUT_DEFAULT;
end;

destructor TSessionController.Destroy;
begin
  inherited Destroy;
  if Assigned(FIniFile) then
    FreeAndNil(FIniFile);
end;

function TSessionController.StartSession: boolean;
begin
  Result := False;
  if FSessionStarted then
    Exit;
  FIniFile := CreateIniFile(FSessionDir + '/' + FSessionID + FSessionExtension);
  if FIniFile = nil then
    Exit;

  // init session
  if not FIniFile.ReadBool(_SESSION_SESSION, _SESSION_ACTIVE, False) then
  begin
    FIniFile.WriteBool(_SESSION_SESSION, _SESSION_ACTIVE, True);
    FIniFile.WriteInteger(_SESSION_SESSION, _SESSION_KEYTIMEOUT, FSessionTimeout);
    FIniFile.WriteDateTime(_SESSION_SESSION, _SESSION_KEYSTART, now);
    FIniFile.WriteDateTime(_SESSION_SESSION, _SESSION_KEYLAST, now);
  end;

  // check if expired
  if GetIsExpired then
  begin
    {
    DeleteIniFile;
    FreeAndNil(FIniFile);
    FSessionTerminated:=True;
    }
    Exit;
  end;

  FIniFile.WriteDateTime(_SESSION_SESSION, _SESSION_KEYLAST, now);

  if not FCached then
    UpdateIniFile;
  FSessionStarted := True;
  Result := True;
end;

procedure TSessionController.EndSession;
begin
  DeleteIniFile;
  FreeAndNil(FIniFile);
  FSessionTerminated:=True;
end;

procedure TSessionController.Terminate;
begin
  EndSession;
end;

function TSessionController.ReadDateTime(const variable: string): TDateTime;
begin
  Result:=0;
  if (not FSessionStarted)or(FSessionTerminated)or(FIniFile=nil) then Exit;
  Result:=FIniFile.ReadDateTime(_SESSION_DATA,variable,0);
end;

function TSessionController.ReadInteger(const variable: string): Integer;
begin
  Result:=0;
  if (not FSessionStarted)or(FSessionTerminated)or(FIniFile=nil) then Exit;
  Result:=FIniFile.ReadInteger(_SESSION_DATA,variable,0);
end;

end.


