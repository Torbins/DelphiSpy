unit ConnectForm;

{ Finds the applications on the network that link VclSpy.Server, and
  connects to one. Searching and connecting run on threads of their own;
  meanwhile the dialog stays open. }

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, VclSpy.RemoteClient;

type
  TfrmConnect = class(TForm)
    pnlSearch: TPanel;
    lblHosts: TLabel;
    edtHosts: TEdit;
    btnSearch: TButton;
    lvServers: TListView;
    pnlBottom: TPanel;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblStatus: TLabel;
    btnConnect: TButton;
    btnCancel: TButton;
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnSearchClick(Sender: TObject);
    procedure btnConnectClick(Sender: TObject);
    procedure lvServersSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvServersDblClick(Sender: TObject);
  private
    FClient: TRemoteClient;
    FServers: TArray<TRemoteServer>;
    FBusy: Boolean;
    procedure Run(const Status: string; const Work: TProc; const Done: TProc<string>);
    procedure UpdateButtons;
  end;

// Returns True once Client is connected
function ConnectRemote(Owner: TCustomForm; Client: TRemoteClient): Boolean;

implementation

{$R *.dfm}

uses
  System.UITypes, Vcl.Graphics, VclSpy.Protocol;

const
  DiscoveryTimeout = 3000;

var
  // Kept for the next time the dialog opens
  LastHosts, LastPassword: string;

function ConnectRemote(Owner: TCustomForm; Client: TRemoteClient): Boolean;
var
  Dialog: TfrmConnect;
begin
  Dialog := TfrmConnect.Create(Owner);
  try
    Dialog.FClient := Client;
    Dialog.edtHosts.Text := LastHosts;
    Dialog.edtPassword.Text := LastPassword;
    Result := Dialog.ShowModal = mrOk;
    LastHosts := Dialog.edtHosts.Text;
    LastPassword := Dialog.edtPassword.Text;
  finally
    Dialog.Free;
  end;
end;

procedure TfrmConnect.FormShow(Sender: TObject);
begin
  UpdateButtons;
  btnSearchClick(nil);
end;

procedure TfrmConnect.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // The thread reports back to this form
  CanClose := not FBusy;
end;

// Work runs on a thread; Done gets its exception's message, or ''
procedure TfrmConnect.Run(const Status: string; const Work: TProc; const Done: TProc<string>);
begin
  FBusy := True;
  lblStatus.Font.Color := clWindowText;
  lblStatus.Caption := Status;
  Screen.Cursor := crHourGlass;
  UpdateButtons;
  TThread.CreateAnonymousThread(
    procedure
    var
      Error: string;
    begin
      Error := '';
      try
        Work;
      except
        on E: Exception do
          Error := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          FBusy := False;
          Screen.Cursor := crDefault;
          UpdateButtons;
          if Error <> '' then
          begin
            lblStatus.Font.Color := clRed;
            lblStatus.Caption := Error;
          end;
          Done(Error);
        end);
    end).Start;
end;

procedure TfrmConnect.UpdateButtons;
begin
  btnSearch.Enabled := not FBusy;
  btnConnect.Enabled := not FBusy and (lvServers.Selected <> nil);
  btnCancel.Enabled := not FBusy;
end;

procedure TfrmConnect.btnSearchClick(Sender: TObject);
var
  Hosts, Where: string;
  Found: TArray<TRemoteServer>;
begin
  if FBusy then
    Exit;
  Hosts := Trim(edtHosts.Text);
  lvServers.Items.Clear;
  FServers := nil;
  Where := Hosts;
  if Where = '' then
    Where := 'the local network';
  Run('Searching ' + Where + ' ...',
    procedure
    begin
      Found := FClient.Discover(Hosts, DiscoveryTimeout);
    end,
    procedure(Error: string)
    var
      Server: TRemoteServer;
      Item: TListItem;
    begin
      if Error <> '' then
        Exit;
      FServers := Found;
      for Server in FServers do
      begin
        Item := lvServers.Items.Add;
        Item.Caption := Server.Description;
        Item.SubItems.Add(Server.Address);
      end;
      if lvServers.Items.Count > 0 then
      begin
        lvServers.Items[0].Selected := True;
        lvServers.Items[0].Focused := True;
        lvServers.SetFocus;
        lblStatus.Caption := Format('Found %d application(s) with VclSpy.Server.', [Length(FServers)]);
      end
      else
        lblStatus.Caption := 'Found no application with VclSpy.Server. Name its computer above if it ' +
          'is in another network.';
      UpdateButtons;
    end);
end;

procedure TfrmConnect.btnConnectClick(Sender: TObject);
var
  Server: TRemoteServer;
  Password: string;
begin
  if FBusy or (lvServers.Selected = nil) then
    Exit;
  Server := FServers[lvServers.Selected.Index];
  Password := edtPassword.Text;
  Run('Connecting to ' + Server.Caption + ' ...',
    procedure
    begin
      FClient.Connect(Server, Password, VclSpyRemoteTimeout);
    end,
    procedure(Error: string)
    begin
      if Error = '' then
        ModalResult := mrOk
      else if Error.Contains('password') then
        edtPassword.SetFocus;
    end);
end;

procedure TfrmConnect.lvServersSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TfrmConnect.lvServersDblClick(Sender: TObject);
begin
  btnConnectClick(nil);
end;

end.
