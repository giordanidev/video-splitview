; Script do Inno Setup para o instalador do Video Splitview.
; Os defines (AppVersion, SourceDir, OutputDir, IconFile, OutputBaseName) sao
; passados pelo tool/package.ps1 via ISCC /D...
;
;   ISCC.exe /DAppVersion=0.0.6 /DSourceDir="...\Release" /DOutputDir="...\dist" ^
;           /DIconFile="...\app_icon.ico" /DOutputBaseName=video-splitview-v0.0.6-windows-x64-setup ^
;           tool\installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef IconFile
  #define IconFile "..\windows\runner\resources\app_icon.ico"
#endif
; Nome do ficheiro do instalador (video-splitview-v<ver>-windows-x64-setup);
; passado pelo tool/package.ps1 via /DOutputBaseName=...
#ifndef OutputBaseName
  #define OutputBaseName="video-splitview-v" + AppVersion + "-windows-x64-setup"
#endif

[Setup]
AppId={{9E2B4C7A-5D31-4F6E-9C2A-1B8F3D6E7A40}
AppName=Video Splitview
AppVersion={#AppVersion}
AppVerName=Video Splitview {#AppVersion}
AppPublisher=Giordani.dev
AppComments=Side by side, frame by frame.
DefaultDirName={autopf}\Video Splitview
DefaultGroupName=Video Splitview
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\video-splitview.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Inglês (en-US) primeiro: é a língua por omissão do instalador.
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\video-splitview.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Video Splitview"; Filename: "{app}\video-splitview.exe"
Name: "{autodesktop}\Video Splitview"; Filename: "{app}\video-splitview.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\video-splitview.exe"; Description: "{cm:LaunchProgram,Video Splitview}"; Flags: nowait postinstall skipifsilent
