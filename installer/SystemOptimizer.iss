; Installer του Ultimate System Optimizer (Inno Setup 6).
; Build: build-installer.bat (φτιάχνει πρώτα το SystemOptimizer.exe και μετά το setup στο dist\).
;
; Εγκαθιστά στο C:\Program Files\Ultimate System Optimizer, προσθέτει συντόμευση στο μενού Έναρξη
; (προαιρετικά και στην επιφάνεια εργασίας) και καταχώριση στις «Εγκατεστημένες εφαρμογές» με
; uninstaller. Ο launcher αναγνωρίζει την εγκατάσταση στο Program Files και γράφει ρυθμίσεις,
; ιστορικό και log στο %LOCALAPPDATA%\SystemOptimizer.

#define AppName      "Ultimate System Optimizer"
#define AppVersion   "7.0"
#define AppPublisher "Kwstas (kwstas147)"
#define AppUrl       "https://github.com/kwstas147/SystemOptimizer"
#define AppExe       "SystemOptimizer.exe"
; Ίδιο με το SetCurrentProcessExplicitAppUserModelID του SystemOptimizer.ps1: έτσι η γραμμή
; εργασιών συνδέει το παράθυρο με τη συντόμευση (σωστό εικονίδιο και καρφίτσωμα).
#define AppUserModelId "Kwstas147.UltimateSystemOptimizer"

[Setup]
; Το AppId δεν αλλάζει ποτέ: με αυτό οι νέες εκδόσεις αναβαθμίζουν την υπάρχουσα εγκατάσταση.
AppId={{5FB2AB50-D33E-4464-8F93-EEC34A3F9AD9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
AppCopyright=Copyright (c) 2026 {#AppPublisher}
VersionInfoVersion={#AppVersion}.0.0
VersionInfoDescription={#AppName} Setup
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible or x86compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile=..\LICENSE
SetupIconFile=..\SystemOptimizer.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
OutputDir=..\dist
OutputBaseFilename=SystemOptimizer-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=auto
LanguageDetectionMethod=uilanguage
CloseApplications=yes
; Τα δεδομένα του χρήστη ζουν σκόπιμα στο %LOCALAPPDATA% (τα γράφει η ίδια η εφαρμογή)
UsedUserAreasWarning=no

[Languages]
Name: "el"; MessagesFile: "Languages\Greek.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
el.AppComment=Καθαρισμός Windows για developers
en.AppComment=Windows clean-up tool for developers
el.DeleteUserData=Να διαγραφούν και οι ρυθμίσεις, το ιστορικό καθαρισμών και το αρχείο καταγραφής;%n%n%1%n%nΑν πατήσετε «Όχι», θα χρησιμοποιηθούν ξανά σε μια μελλοντική εγκατάσταση.
en.DeleteUserData=Also delete the settings, clean-up history and log file?%n%n%1%n%nIf you choose "No", they will be used again by a future installation.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; DestName: "THIRD_PARTY_NOTICES.txt"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "{cm:AppComment}"; AppUserModelID: "{#AppUserModelId}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "{cm:AppComment}"; AppUserModelID: "{#AppUserModelId}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Προσωρινά αρχεία της εφαρμογής: διαγράφονται πάντα
Type: files; Name: "{localappdata}\SystemOptimizer\SystemOptimizer.ps1"
Type: dirifempty; Name: "{localappdata}\SysOptimizer_empty"

[Code]
// Τα δεδομένα του χρήστη (ρυθμίσεις, ιστορικό, log) διαγράφονται μόνο αν το επιβεβαιώσει.
// Στη σιωπηλή απεγκατάσταση διατηρούνται.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;
  DataDir := ExpandConstant('{localappdata}\SystemOptimizer');
  if not DirExists(DataDir) then
    Exit;
  if SuppressibleMsgBox(FmtMessage(CustomMessage('DeleteUserData'), [DataDir]),
                        mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES then
    DelTree(DataDir, True, True, True)
  else
    RemoveDir(DataDir);
end;
