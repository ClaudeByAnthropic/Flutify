#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BuildDir
  #error BuildDir is required
#endif
#ifndef OutputPath
  #error OutputPath is required
#endif
#ifndef ArtifactName
  #error ArtifactName is required
#endif
#ifndef AppArch
  #define AppArch "x64"
#endif

[Setup]
AppId=Flutify
AppName=Flutify
AppVersion={#AppVersion}
AppPublisher=Flutify
AppPublisherURL=https://github.com/is-hp-is-mad/Flutify
AppSupportURL=https://github.com/is-hp-is-mad/Flutify/issues
DefaultDirName={localappdata}\Programs\Flutify
DefaultGroupName=Flutify
DisableProgramGroupPage=yes
DisableDirPage=no
PrivilegesRequired=lowest
#if AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
MinVersion=10.0.17763
OutputDir={#OutputPath}
OutputBaseFilename={#ArtifactName}-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Flutify.exe
LicenseFile={#BuildDir}\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Flutify"; Filename: "{app}\Flutify.exe"; WorkingDir: "{app}"; AppUserModelID: "Flutify"
Name: "{autodesktop}\Flutify"; Filename: "{app}\Flutify.exe"; WorkingDir: "{app}"; AppUserModelID: "Flutify"; Tasks: desktopicon

[Run]
Filename: "{app}\Flutify.exe"; Description: "{cm:LaunchProgram,Flutify}"; Flags: nowait postinstall skipifsilent

; Only installed program files are removed. User profiles and FlutifyCache are
; intentionally absent from UninstallDelete, including portable cache folders.
