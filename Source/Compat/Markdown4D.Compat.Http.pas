unit Markdown4D.Compat.Http;
{ The small part of System.Net.HttpClient the image downloader uses, over
  FPC's fphttpclient.  Redirects are not followed here either: the caller
  judges every hop, so AllowRedirect stays off unless it is asked for. }

{$mode delphiunicode}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$H+}

interface

uses
  SysUtils, Classes, fphttpclient, opensslsockets;

type
  TReceiveDataCallback = reference to procedure(const Sender: TObject;
    ContentLength, ReadCount: Int64; var ShouldAbort: Boolean);

  IHTTPResponse = interface
    ['{6C3A1F42-8E2B-4C55-9D19-4B1E7D0A5C21}']
    function GetStatusCode: Integer;
    function GetHeaderValue(const Name: string): string;
    property StatusCode: Integer read GetStatusCode;
    property HeaderValue[const Name: string]: string read GetHeaderValue; default;
  end;

  THTTPClient = class
  private
    FConnectionTimeout: Integer;
    FResponseTimeout: Integer;
    FHandleRedirects: Boolean;
    FReceiveDataCallback: TReceiveDataCallback;
    procedure DataReceived(Sender: TObject; const ContentLength, CurrentPos: Int64);
  public
    constructor Create;
    function Get(const AURL: string; const ResponseContent: TStream): IHTTPResponse;
    property ConnectionTimeout: Integer read FConnectionTimeout write FConnectionTimeout;
    property ResponseTimeout: Integer read FResponseTimeout write FResponseTimeout;
    property HandleRedirects: Boolean read FHandleRedirects write FHandleRedirects;
    property ReceiveDataCallback: TReceiveDataCallback
      read FReceiveDataCallback write FReceiveDataCallback;
  end;

implementation

type
  TM4DHttpResponse = class(TInterfacedObject, IHTTPResponse)
  private
    FStatusCode: Integer;
    FHeaders: TStringList;
    function GetStatusCode: Integer;
    function GetHeaderValue(const Name: string): string;
  public
    constructor Create(const StatusCode: Integer; const Headers: TStrings);
    destructor Destroy; override;
  end;

constructor TM4DHttpResponse.Create(const StatusCode: Integer;
  const Headers: TStrings);
var
  Index: Integer;
begin
  inherited Create;
  FStatusCode := StatusCode;
  FHeaders := TStringList.Create;
  FHeaders.NameValueSeparator := ':';
  if Headers <> nil then
    for Index := 0 to Headers.Count - 1 do
      FHeaders.Add(Headers[Index]);
end;

destructor TM4DHttpResponse.Destroy;
begin
  FHeaders.Free;
  inherited Destroy;
end;

function TM4DHttpResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

function TM4DHttpResponse.GetHeaderValue(const Name: string): string;
begin
  Result := Trim(FHeaders.Values[Name]);
end;

constructor THTTPClient.Create;
begin
  inherited Create;
  FConnectionTimeout := 30000;
  FResponseTimeout := 60000;
  FHandleRedirects := True;
end;

procedure THTTPClient.DataReceived(Sender: TObject;
  const ContentLength, CurrentPos: Int64);
var
  Abort: Boolean;
begin
  if not Assigned(FReceiveDataCallback) then
    Exit;
  Abort := False;
  FReceiveDataCallback(Sender, ContentLength, CurrentPos, Abort);
  if Abort then
    raise EAbort.Create('download aborted');
end;

type
  TM4DAbort = class(TObject)
  end;

function THTTPClient.Get(const AURL: string;
  const ResponseContent: TStream): IHTTPResponse;
var
  Client: TFPHTTPClient;
  Status: Integer;
  Headers: TStringList;
begin
  Client := TFPHTTPClient.Create(nil);
  Headers := TStringList.Create;
  try
    Client.ConnectTimeout := FConnectionTimeout;
    Client.IOTimeout := FResponseTimeout;
    Client.AllowRedirect := FHandleRedirects;
    if Assigned(FReceiveDataCallback) then
      Client.OnDataReceived := DataReceived;
    Status := 0;
    try
      Client.Get(AURL, ResponseContent);
      Status := Client.ResponseStatusCode;
      Headers.Assign(Client.ResponseHeaders);
    except
      // FPC raises on any status it does not treat as success, including the
      // 3xx responses the downloader follows itself. Keep the status and the
      // headers (Location) so the caller can judge the redirect; otherwise the
      // exception escapes and the caller sees an ordinary failure.
      on E: EHTTPClient do
      begin
        Status := Client.ResponseStatusCode;
        Headers.Assign(Client.ResponseHeaders);
      end;
      // an aborted or failed transfer still reports whatever arrived
      on EAbort do
        Status := Client.ResponseStatusCode;
    end;
    Result := TM4DHttpResponse.Create(Status, Headers);
  finally
    Headers.Free;
    Client.Free;
  end;
end;

end.
