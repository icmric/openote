; Openote — Windows installer (Inno Setup)
;
; Produces the single setup .exe that the release workflow ships beside the
; portable zip. See docs/planning/v0.7-packaging.md for why Inno Setup and why
; a per-user install.
;
; Built in CI as:
;   iscc /DAppVersion=<x.y.z> /DStageDir=<staged build dir> openote.iss
;
; StageDir is the directory the workflow has already assembled — openote.exe,
; the Flutter runtime DLLs, onote_core.dll and the data/ tree. Everything in it
; is installed by WILDCARD on purpose: when the app gains another bundled
; native library, this file does not need to change. Packaging that breaks
; every time the app grows is packaging nobody maintains.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef StageDir
  #define StageDir "..\..\app\build\windows\x64\runner\Release"
#endif

#define AppName "Openote"
#define AppPublisher "Openote"
#define AppUrl "https://github.com/icmric/openote"
#define AppExe "openote.exe"

[Setup]
; A stable GUID identifies the *product* across versions — it is what makes an
; upgrade replace the previous install rather than sit beside it, and what lets
; Add/Remove Programs find it. Never change it.
AppId={{8E5C0C41-6C2E-4E2C-9E5B-1F7A2D2F1A10}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
VersionInfoVersion={#AppVersion}

; ── Per-user install: no administrator prompt ────────────────────────────
; Installs into %LOCALAPPDATA%\Programs\Openote. A student on a university
; laptop is often not an administrator on it, and a notebook is personal
; software — asking for the whole machine buys nothing and can block the
; install outright. See v0.7 §2.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes

; The uninstaller, and the Add/Remove Programs entry that points at it.
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}

LicenseFile=..\..\LICENSE
OutputDir=.
OutputBaseFilename=openote-{#AppVersion}-windows-x64-setup
; The app's own Windows icon, so the setup exe, the Start-menu entry and
; the running app are all visibly the same program.
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Refuse to install over a running copy rather than leaving a half-updated
; directory — the failure mode where the exe is replaced but a DLL beside it is
; not is exactly the stale-library trap this project has already paid for once.
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; \
  GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; Everything the workflow staged, recursively. `recursesubdirs createallsubdirs`
; carries Flutter's data/ tree (the bundled fonts, the spell-check wordlist,
; the icon) as well as the DLLs.
;
; The FFI loader looks for onote_core.dll NEXT TO the exe first, so the flat
; layout of the staging directory is load-bearing — do not "tidy" the DLLs into
; a lib/ subfolder.
Source: "{#StageDir}\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; \
  Description: "Launch {#AppName}"; \
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Only what the installer itself created. **The user's notebooks live in their
; own workspace directory and are never touched** — an uninstaller that deletes
; someone's notes because they wanted to reinstall would be unforgivable, and
; the open-format promise means those files must outlive the app that made them.
Type: filesandordirs; Name: "{app}\data"
Type: dirifempty; Name: "{app}"
