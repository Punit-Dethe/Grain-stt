; ─────────────────────────────────────────────────────────────────────────────
; Grain STT — Inno Setup installer script
;
; Prerequisites:
;   1. Build the app first:  python -m PyInstaller grain_stt.spec --noconfirm
;   2. Install Inno Setup 6:  https://jrsoftware.org/isdl.php
;   3. Open this file in Inno Setup and click Compile  (or: iscc installer.iss)
;
; Output: installer/GrainSTT-Setup.exe
; ─────────────────────────────────────────────────────────────────────────────

#define AppName      "Grain"
#define AppVersion   "1.0.0"
#define AppPublisher "Grain"
#define AppURL       "https://github.com/your-username/grain-stt"
#define AppExe       "GrainSTT.exe"
#define BuildDir     "dist\GrainSTT"

[Setup]
; Unique ID — regenerate with Tools > Generate GUID if you fork this project
AppId={{A3F2C1D4-7B8E-4F6A-9C0D-2E5F8A3B1C7D}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}

; Install to Program Files (32/64-bit aware)
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes

; Require admin so it installs to Program Files properly
PrivilegesRequired=admin

; Compression
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes

; Output
OutputDir=installer
OutputBaseFilename=GrainSTT-Setup
SetupIconFile=

; Windows version guard — Win 10 1809+ (build 17763)
MinVersion=10.0.17763

; Architecture
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

; Uninstall settings — shows up in Apps & Features
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}

; Wizard appearance
WizardStyle=modern
WizardSmallImageFile=
DisableWelcomePage=no
DisableReadyPage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";   Description: "Create a &desktop shortcut";    GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startupentry";  Description: "Launch Grain at &Windows startup"; GroupDescription: "System integration:"; Flags: unchecked

[Files]
; Copy everything PyInstaller collected into the install directory
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu
Name: "{group}\{#AppName}";          Filename: "{app}\{#AppExe}"; Comment: "Open voice layer for dictation and AI"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

; Desktop shortcut (optional, off by default)
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Startup entry (optional, off by default)
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
  ValueType: string; ValueName: "{#AppName}"; \
  ValueData: """{app}\{#AppExe}"""; \
  Flags: uninsdeletevalue; Tasks: startupentry

[Run]
; Offer to launch the app after installation
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
; Kill the running process before uninstall so files can be removed
Filename: "taskkill.exe"; Parameters: "/f /im {#AppExe}"; Flags: runhidden; RunOnceId: "KillGrain"

[UninstallDelete]
; Clean up any log files left behind in the install directory
Type: filesandordirs; Name: "{app}\logs"
