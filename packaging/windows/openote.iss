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
; The ProgID is the registry name for "a thing Openote opens". Versioned-looking
; on purpose (this is the convention Windows expects) and, like AppId, never
; changed once shipped: it is what an existing association points at.
;
; `LinkProgId` is what v0.17 registers; `OldNotebookProgId` is the `.onote`
; registration it RETIRES, kept here by its literal old name because the
; deletion entries below have to name the key that is actually on the machine.
; A new name rather than a reused one: reusing "Openote.Notebook.1" would mean
; the deletion and the creation in the same [Registry] section fighting over
; one key, decided by line order.
#define LinkProgId "Openote.NotebookLink.1"
#define OldNotebookProgId "Openote.Notebook.1"
; The pointer file's extension. Spelled once: it appears on four registry keys
; below and must match `notebookPointerExtension` in app/lib/core/open_target.dart
; and the glob in packaging/linux/openote.xml.
#define PointerExt ".onotelink"

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
; No `PrivilegesRequiredOverridesAllowed=dialog`. It made Inno open with an
; install-mode page offering a UAC-shielded "for all users" option as the very
; FIRST thing the user saw — directly contradicting the release notes, which
; promise the installer never asks for an administrator password. Per-machine
; install is not a supported configuration yet (v0.7 §2), so offering it was
; offering a path nobody had tested.
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

; Tells Inno to call SHChangeNotify(SHCNE_ASSOCCHANGED) when it finishes, so
; Explorer picks up the associations below without a sign-out. Without it the
; icon and the double-click behaviour appear at some unpredictable later
; moment, which reads as "the installer didn't work". It matters twice over
; from v0.17: this upgrade REMOVES the .onote association as well as adding
; the new one, and a stale "opens with Openote" left in Explorer's cache is
; exactly the entry a student would use to clone a dead working copy.
ChangesAssociations=yes

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

[Registry]
; ── RETIRE the .onote association (v0.17 Step 8b) ────────────────────────
;
; These deletions come FIRST in the section, and they are not optional.
;
; Inno removes registry entries at UNINSTALL, and never merely because a line
; has vanished from this script. So deleting the old registration lines would
; have left `.onote` pointing at Openote on every machine that already ran an
; older installer, for ever — and the in-app updater (update_dialog.dart runs
; this setup with /SILENT under the same AppId) is exactly that path. An
; upgrade that "removed" the association by omission would have removed it only
; from machines that never had it.
;
; What it costs to get wrong: from v0.17 the container is a local-only working
; copy named `cache.onote`, and after Step 7 its blobs table is EMPTY. A
; student who double-clicks one through a stale association gets a notebook
; with every picture missing that still passes an integrity check. The app
; refuses it by name and by user_version (app/lib/core/open_target.dart), and
; this is the half that stops Explorer offering in the first place.
;
; The asymmetry is the same one the registration comments explained, for the
; same reason: delete the VALUE on keys other programs share (`.onote` itself,
; `OpenWithProgids`, `SupportedTypes`), delete the KEY only where the whole
; tree is ours (our own ProgID).
Root: HKA; Subkey: "Software\Classes\.onote"; ValueType: none; \
  ValueName: ""; Flags: deletevalue
Root: HKA; Subkey: "Software\Classes\.onote"; ValueType: none; \
  ValueName: "Content Type"; Flags: deletevalue
Root: HKA; Subkey: "Software\Classes\.onote\OpenWithProgids"; ValueType: none; \
  ValueName: "{#OldNotebookProgId}"; Flags: deletevalue
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; \
  ValueType: none; ValueName: ".onote"; Flags: deletevalue
; Ours entirely, so the key goes with its DefaultIcon and shell\open\command.
Root: HKA; Subkey: "Software\Classes\{#OldNotebookProgId}"; ValueType: none; \
  Flags: deletekey

; ── Double-click a notebook and it opens ─────────────────────────────────
;
; The point of the whole feature: "A year 10 student wont know what an MCP is
; or how to run a command in their terminal", so the file-manager route is the
; one that matters and the command line is the power-user spelling of it.
;
; **What is registered is a POINTER FILE, and that is a fallback, not the
; decision.** The decision was "register the folder instead" — associate the
; `.onotebook` directory. Windows associates EXTENSIONS, and a directory name
; has none. The two mechanisms that exist are a `Directory\shell\<verb>` entry,
; which would put "Open with Openote" on the context menu of every folder on
; the machine and STILL not change what a double-click does, and a registered
; shell namespace extension, which is a COM DLL and far outside what a per-user
; install can or should do. So each `.onotebook` carries a small file —
; `Open this notebook.onotelink`, written by app/lib/sync/op_log.dart — and
; that file is what these entries associate. A student opens the folder they
; were sent and double-clicks the one thing in it with the Openote icon.
;
; `HKA` (HKEY_AUTO) resolves to HKEY_CURRENT_USER here, because
; PrivilegesRequired=lowest above means this install never has the rights to
; write HKEY_LOCAL_MACHINE. HKCU\Software\Classes is a first-class association
; on every supported Windows — it just belongs to the person rather than to the
; machine, which is right for a per-user install of personal software.
;
; `uninsdeletevalue` on the extension and `uninsdeletekey` on the ProgID: an
; uninstall must leave no ".onotelink opens with a program that is gone"
; behind. Note the asymmetry — the extension key gets its VALUE removed, not
; the key, because another program may have added its own entries under it.
Root: HKA; Subkey: "Software\Classes\{#PointerExt}"; ValueType: string; \
  ValueName: ""; ValueData: "{#LinkProgId}"; Flags: uninsdeletevalue
; The MIME type Openote declares to Linux desktops for the same file
; (packaging/linux/openote.xml). Kept identical so a notebook folder carried
; between platforms is described the same way at both ends.
Root: HKA; Subkey: "Software\Classes\{#PointerExt}"; ValueType: string; \
  ValueName: "Content Type"; ValueData: "application/x-onote-link"; \
  Flags: uninsdeletevalue
; What Explorer calls it in the Type column. Plain words, no file format — and
; "shortcut" rather than "notebook", because the notebook is the folder around
; it and calling both the same thing is how somebody emails the wrong one.
Root: HKA; Subkey: "Software\Classes\{#LinkProgId}"; ValueType: string; \
  ValueName: ""; ValueData: "Openote notebook shortcut"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#LinkProgId}\DefaultIcon"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"
; The quoting is load-bearing. `"%1"` — the inner quotes are part of the
; registry value — is what keeps
; `C:\My Notes\Term 1.onotebook\Open this notebook.onotelink` a single
; argument; without them Windows hands over `C:\My`, and every notebook in a
; folder with a space in its name fails to open. The pointer file's own name
; has a space in it *always*, so this is no longer the unlucky case — it is
; every case. (In an Inno string, `""` is one literal quote.)
Root: HKA; Subkey: "Software\Classes\{#LinkProgId}\shell\open\command"; \
  ValueType: string; ValueName: ""; \
  ValueData: """{app}\{#AppExe}"" ""%1"""
; "Open with ▸ Openote" even when something else owns the default — the way
; back for anyone who has pointed .onotelink somewhere else, without hunting
; for the exe. `uninsdeletevalue` again: this key is shared with every other
; program that has ever offered to open one.
Root: HKA; Subkey: "Software\Classes\{#PointerExt}\OpenWithProgids"; \
  ValueType: string; ValueName: "{#LinkProgId}"; ValueData: ""; \
  Flags: uninsdeletevalue
; The per-application registration behind that entry. `uninsdeletekey` sits on
; the ROOT of this little tree, not on the command key: put it on the leaf and
; the uninstall takes `\shell\open\command` away and leaves `SupportedTypes`
; behind, which is a half-registered application in the shell forever.
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}"; \
  ValueType: none; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; \
  ValueType: string; ValueName: ""; \
  ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; \
  ValueType: string; ValueName: "{#PointerExt}"; ValueData: ""

[Run]
Filename: "{app}\{#AppExe}"; \
  Description: "Launch {#AppName}"; \
  Flags: nowait postinstall skipifsilent
; Silent installs are the update-through-app path: update_dialog.dart runs
; this setup with /SILENT after the app saves and exits. `skipifsilent`
; above rightly skips the interactive launch checkbox — this entry is its
; silent twin, so an in-app update ends with the NEW Openote open,
; completing "apply the update and relaunch" with no user action at all.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: RelaunchAfterSilentUpdate

[Code]
function RelaunchAfterSilentUpdate: Boolean;
begin
  Result := WizardSilent;
end;

[UninstallDelete]
; Only what the installer itself created. **The user's notebooks live in their
; own workspace directory and are never touched** — an uninstaller that deletes
; someone's notes because they wanted to reinstall would be unforgivable, and
; the open-format promise means those files must outlive the app that made them.
Type: filesandordirs; Name: "{app}\data"
Type: dirifempty; Name: "{app}"
