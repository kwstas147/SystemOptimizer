#Requires -Version 5.1
<#
    ULTIMATE SYSTEM OPTIMIZER - v7 (GUI Edition)
    Γραφική έκδοση του optimizer.bat: διαλέγετε με κουτάκια τι θα καθαριστεί.
    Νέο στην v7:
     - Ελληνικά / English (κουμπί στην κεφαλίδα).
     - Σελίδα «Μεγάλα αρχεία & node_modules».
     - Σελίδα «Ιστορικό» με γράφημα του χώρου που ελευθερώθηκε.
     - Νέες κατηγορίες: Discord, Spotify, Teams, NuGet, Yarn, Flutter pub-cache,
       συμπίεση δίσκων WSL/Docker, Windows.old, crash dumps, Prefetch.
     - Σκοτεινό / φωτεινό θέμα.
    Κωδικοποίηση αρχείου: UTF-8 με BOM (απαραίτητο για τα ελληνικά στο PowerShell 5.1).
    Εκκίνηση: διπλό κλικ στο "Start-Optimizer.bat" (ζητά μόνο του δικαιώματα Διαχειριστή).
#>
param(
    [string]$DataDir,    # φάκελος για ρυθμίσεις/ιστορικό/log (το δίνει το .exe)
    [string]$IconPath    # αρχείο για το εικονίδιο του παραθύρου (το .exe)
)

# ============================================================
#  Ανύψωση σε Διαχειριστή / Elevation
# ============================================================
$SelfPath = $PSCommandPath
if (-not $SelfPath) { $SelfPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    try {
        if ($SelfPath -like '*.ps1') {
            Start-Process powershell.exe -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$SelfPath`"",
                '-DataDir', "`"$DataDir`"", '-IconPath', "`"$IconPath`"")
        } else {
            Start-Process -FilePath $SelfPath -Verb RunAs
        }
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show("Απαιτούνται δικαιώματα Διαχειριστή.`nAdministrator rights are required.", 'System Optimizer', 'OK', 'Error')
    }
    exit
}

$BaseDir = if ($DataDir -and (Test-Path -LiteralPath $DataDir)) { $DataDir.TrimEnd('\') }
           elseif ($PSScriptRoot) { $PSScriptRoot } else { [AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\') }

# Αρχεία δίπλα στο script, αλλιώς σε %TEMP% / %LOCALAPPDATA%
function Get-WritablePath([string]$name, [string]$fallbackDir) {
    $p = Join-Path $BaseDir $name
    try { [IO.File]::AppendAllText($p, ''); return $p } catch { return (Join-Path $fallbackDir $name) }
}
$LogPath      = Get-WritablePath 'optimizer_log.txt' $env:TEMP
$SettingsPath = Get-WritablePath 'SystemOptimizer.settings.json' $env:LOCALAPPDATA
$HistoryPath  = Get-WritablePath 'SystemOptimizer.history.json' $env:LOCALAPPDATA

function Read-JsonFile([string]$p) {
    try {
        if ((Get-Item -LiteralPath $p -ErrorAction Stop).Length -gt 0) {
            return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
    } catch { }
    return $null
}
$Settings = Read-JsonFile $SettingsPath

$InitialLang = if ($Settings -and @('el', 'en') -contains $Settings.Lang) { $Settings.Lang }
               elseif ((Get-Culture).TwoLetterISOLanguageName -eq 'el') { 'el' } else { 'en' }

# --- Κοινή κατάσταση UI <-> worker ---
$sync = [hashtable]::Synchronized(@{
    Queue        = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    Cancel       = $false
    Lang         = $InitialLang
    Mode         = ''
    Items        = @()
    Names        = @{}
    ProjectsRoot = ''
    KillList     = ''
    ScanRoot     = ''
    MinBytes     = [int64]0
    DeleteList   = @()
    UseRecycle   = $true
    LogPath      = $LogPath
    EmptyDir     = (Join-Path $env:LOCALAPPDATA 'SysOptimizer_empty')
})

# ============================================================
#  ΚΕΙΜΕΝΑ / STRINGS (el + en) - κοινά για UI και worker
# ============================================================
$LangCore = @'
$Str = @{
  el = @{
    'grp.win' = 'Windows'; 'grp.ide' = 'IDE & Επεξεργαστές κώδικα'; 'grp.dev' = 'Εργαλεία ανάπτυξης'
    'grp.web' = 'Φυλλομετρητές'; 'grp.app' = 'Εφαρμογές'; 'grp.custom' = 'Δικοί μου φάκελοι'
    'lang.button' = 'English'
    'theme.toDark' = '☾  Σκοτεινό θέμα'; 'theme.toLight' = '☀  Φωτεινό θέμα'
    'nav.clean' = 'Καθαρισμός'; 'nav.big' = 'Μεγάλα αρχεία & node_modules'; 'nav.hist' = 'Ιστορικό'
    'btn.stop' = 'Διακοπή'; 'btn.log' = 'Αρχείο καταγραφής'; 'btn.all' = 'Όλα'; 'btn.none' = 'Κανένα'
    'btn.defaults' = 'Προεπιλογές'; 'btn.addDir' = '+ Φάκελος...'; 'btn.delDir' = 'Αφαίρεση φακέλου'
    'btn.clean' = 'Καθαρισμός τώρα'; 'btn.scan' = 'Σάρωση μεγέθους'
    'btn.findBig' = 'Βρες μεγάλα αρχεία'; 'btn.findDev' = 'Βρες node_modules / venv'
    'btn.delSel' = 'Διαγραφή επιλεγμένων'; 'btn.openLoc' = 'Άνοιγμα θέσης'; 'btn.histClear' = 'Διαγραφή ιστορικού'
    'box.desc' = 'Περιγραφή'; 'box.opt' = 'Ρυθμίσεις'; 'box.log' = 'Καταγραφή'
    'opt.projects' = 'Φάκελος projects:'; 'opt.kill' = 'Εφαρμογές για τερματισμό:'
    'status.ready' = 'Έτοιμο.'
    'desc.initial' = 'Επιλέξτε μια εργασία για να δείτε τι ακριβώς καθαρίζει και ποιοι φάκελοι υπάρχουν στον υπολογιστή σας.'
    'lbl.searchIn' = 'Αναζήτηση σε:'; 'lbl.minSize' = 'Ελάχιστο μέγεθος (MB):'
    'big.hint' = 'Τικάρετε ό,τι θέλετε να διαγραφεί. Διπλό κλικ = άνοιγμα της θέσης στην Εξερεύνηση. Κλικ σε στήλη = ταξινόμηση.'
    'chk.recycle' = 'Αρχεία στον Κάδο (ασφαλέστερο)'
    'big.selected' = 'Επιλεγμένα: {0}  -  {1}'
    'col.path' = 'Διαδρομή'; 'col.size' = 'Μέγεθος'; 'col.modified' = 'Τελευταία αλλαγή'; 'col.type' = 'Τύπος'
    'col.date' = 'Ημερομηνία'; 'col.freed' = 'Ελευθερώθηκαν'; 'col.freeAfter' = 'Ελεύθερος χώρος μετά'
    'col.duration' = 'Διάρκεια'; 'col.tasks' = 'Εργασίες'; 'col.note' = 'Σημείωση'
    'tip.kill' = 'Ονόματα .exe χωρισμένα με κενό, κόμμα ή ερωτηματικό'
    'tip.scan' = 'Υπολογίζει πόσο χώρο πιάνει κάθε κατηγορία (δεν διαγράφει τίποτα)'
    'tip.findDev' = 'Βρίσκει node_modules, venv/.venv, __pycache__, .next, .nuxt, .turbo, .parcel-cache, .angular. Ξαναδημιουργούνται με npm install / pip install.'
    'tip.recycle' = 'Τα αρχεία πηγαίνουν στον Κάδο. Οι φάκελοι node_modules / venv διαγράφονται πάντα οριστικά (είναι χιλιάδες μικρά αρχεία).'
    'tip.lang' = 'Switch to English'
    'total.known' = 'Επιλεγμένα: {0}  -  εκτιμώμενος χώρος: {1}'
    'total.unknown' = 'Επιλεγμένα: {0}  (πατήστε «Σάρωση μεγέθους» για εκτίμηση)'
    'free.header' = 'Ελεύθερος χώρος {0}  {1}     |     Αρχείο καταγραφής: {2}'
    'desc.group' = 'Ομάδα «{0}». Τικάρετε την ομάδα για να επιλέξετε όλες τις εργασίες της.'
    'desc.custom' = 'Δικός σας φάκελος: αδειάζουν ΟΡΙΣΤΙΚΑ όλα τα περιεχόμενά του (όχι στον Κάδο). Ο ίδιος ο φάκελος διατηρείται.'
    'desc.wsl' = 'Εικονικοί δίσκοι που βρέθηκαν ({0}):'
    'desc.found' = 'Φάκελοι που βρέθηκαν ({0} από {1}):'
    'desc.more' = '  ... και {0} ακόμη'
    'desc.none' = '  (κανένας - δεν υπάρχει κάτι για καθάρισμα)'
    'done.summary' = "Ελευθερώθηκαν: {0}`nΕλεύθερος χώρος τώρα: {1}`nΧρόνος: {2}"
    'done.cleanOk' = 'Ο καθαρισμός ολοκληρώθηκε.'; 'done.cleanCancel' = 'Ο καθαρισμός διακόπηκε.'
    'done.delete' = 'Η διαγραφή ολοκληρώθηκε - ελευθερώθηκαν {0}.'
    'done.found' = 'Βρέθηκαν {0} αποτελέσματα.'
    'hist.sum' = 'Συνολικά ελευθερώθηκαν {0} σε {1} καθαρισμούς  -  μέσος όρος {2}'
    'hist.empty' = 'Δεν υπάρχει ακόμη ιστορικό. Μετά από κάθε καθαρισμό θα εμφανίζεται εδώ.'
    'hist.cancelled' = 'Διακόπηκε'
    'hist.clearConfirm' = 'Διαγραφή όλου του ιστορικού καθαρισμών;'; 'hist.title' = 'Ιστορικό'
    'chart.title' = 'Χώρος που ελευθερώθηκε ανά καθαρισμό (τελευταίοι 20)'
    'chart.empty' = 'Δεν υπάρχει ακόμη ιστορικό - κάντε έναν καθαρισμό.'
    'chart.tip' = "{0}`nΕλευθερώθηκαν: {1}`nΕλεύθερος χώρος μετά: {2}`nΔιάρκεια: {3}`nΕργασίες: {4}"
    'msg.protected' = "Ο φάκελος είναι προστατευμένος και δεν μπορεί να προστεθεί:`n{0}"; 'msg.protectedTitle' = 'Προστασία'
    'msg.addDir' = "Όταν είναι τικαρισμένος, ΟΛΑ τα περιεχόμενα του φακέλου θα διαγράφονται οριστικά:`n`n{0}`n`nΠροσθήκη;"
    'msg.addDirTitle' = 'Νέος φάκελος'
    'dlg.addDir' = 'Επιλέξτε φάκελο του οποίου τα περιεχόμενα θα αδειάζουν'
    'dlg.projects' = 'Φάκελος με τα Flutter / Android projects'
    'dlg.root' = 'Πού να γίνει η αναζήτηση;'
    'msg.selectCustom' = 'Επιλέξτε πρώτα έναν φάκελο από την ομάδα «Δικοί μου φάκελοι».'
    'msg.noTasks' = 'Δεν έχετε επιλέξει καμία εργασία.'
    'msg.rootMissing' = 'Ο φάκελος αναζήτησης δεν υπάρχει.'
    'msg.checkFirst' = 'Τικάρετε πρώτα όσα θέλετε να διαγραφούν.'
    'msg.busy' = 'Εκτελείται εργασία. Πατήστε «Διακοπή» και περιμένετε να ολοκληρωθεί το τρέχον βήμα.'
    'confirm.tasks' = "Θα εκτελεστούν οι παρακάτω εργασίες:`n`n{0}`n{1}`n`nΣυνέχεια;"; 'confirm.title' = 'Επιβεβαίωση'
    'warn.kill' = '⚠ Οι εφαρμογές της λίστας θα κλείσουν ΧΩΡΙΣ αποθήκευση.'
    'warn.dism' = '⚠ Το DISM διαρκεί 10-20 λεπτά.'
    'warn.wsl' = '⚠ Το WSL θα κλείσει. Κλείστε πρώτα το Docker Desktop.'
    'warn.winold' = '⚠ Μετά τη διαγραφή του Windows.old δεν γίνεται επιστροφή στην προηγούμενη έκδοση Windows.'
    'warn.custom' = '⚠ Τα περιεχόμενα των δικών σας φακέλων διαγράφονται οριστικά.'
    'warn.browsers' = '⚠ Κλείστε τους φυλλομετρητές πριν συνεχίσετε.'
    'del.files' = '•  {0} αρχεία -> {1}'; 'del.toBin' = 'στον Κάδο Ανακύκλωσης'; 'del.permanent' = 'ΟΡΙΣΤΙΚΗ διαγραφή'
    'del.dirs' = '•  {0} φάκελοι -> ΟΡΙΣΤΙΚΗ διαγραφή (ξαναδημιουργούνται με npm install / pip install)'
    'del.confirm' = "Θα διαγραφούν {0} στοιχεία ({1}):`n{2}`n`nΣυνέχεια;"; 'del.title' = 'Επιβεβαίωση διαγραφής'
    'log.scanAll' = 'Σάρωση μεγέθους όλων των κατηγοριών...'
    'log.searchIn' = 'Αναζήτηση σε {0}...'
    'log.stop' = 'Ζητήθηκε διακοπή - θα σταματήσει μετά το τρέχον βήμα...'
    'log.ready' = 'Έτοιμο. Τικάρετε ό,τι θέλετε να καθαριστεί και πατήστε «Καθαρισμός τώρα».'
    'status.scanning' = 'Σάρωση... (σε ολόκληρο δίσκο μπορεί να πάρει 1-3 λεπτά)'
    'w.protected' = '  ΑΣΦΑΛΕΙΑ: παραλείφθηκε {0}'; 'w.empty' = '  Άδειασμα: {0}'; 'w.delete' = '  Διαγραφή: {0}'
    'w.noWsl' = '  Δεν βρέθηκαν δίσκοι WSL / Docker.'
    'w.compress' = '  Συμπίεση: {0} ({1})'; 'w.compressed' = '    -> {0} (κέρδος {1})'
    'w.cleanmgr' = '  Εκτελείται cleanmgr /sagerun:{0} (μπορεί να ανοίξει δικό του παράθυρο)...'
    'w.cleanmgrExit' = '  cleanmgr: κωδικός εξόδου {0}'
    'w.dism' = '  DISM /StartComponentCleanup - υπομονή, 10-20 λεπτά...'
    'w.dismCode' = '  ΠΡΟΕΙΔΟΠΟΙΗΣΗ: το DISM επέστρεψε κωδικό {0}'
    'w.killed' = '  Τερματίστηκε: {0}'; 'w.notRunning' = '  Δεν εκτελείται: {0}'
    'w.noWinOld' = '  Δεν υπάρχει φάκελος Windows.old.'
    'w.svcStop' = '  Διακοπή υπηρεσιών wuauserv, bits'; 'w.svcStart' = '  Οι υπηρεσίες επανεκκινήθηκαν'
    'w.scanProgress' = 'Σάρωση: {0} φάκελοι, {1} αρχεία - {2}'
    'w.bigFound' = 'Βρέθηκαν {0} αρχεία >= {1} σε {2} φακέλους (εμφανίζονται τα {3} μεγαλύτερα).'
    'w.devProgress' = 'Σάρωση: {0} φάκελοι, βρέθηκαν {1} - {2}'
    'w.devFound' = 'Βρέθηκαν {0} φάκελοι ανάπτυξης, συνολικά {1}.'
    'w.toBin' = '  Στον Κάδο: {0}'; 'w.error' = '  ΣΦΑΛΜΑ: {0}'
    'w.scanItem' = 'Σάρωση: {0}'; 'w.scanDone' = 'Η σάρωση ολοκληρώθηκε.'
    'w.start' = '=== ΕΝΑΡΞΗ ΚΑΘΑΡΙΣΜΟΥ - Ελεύθερος χώρος {0} {1} ==='
    'w.cancelled' = 'Διακοπή από τον χρήστη.'
    'w.end' = '=== ΤΕΛΟΣ - Χρόνος {0} - Ελευθερώθηκαν {1} - Ελεύθερος χώρος {2} ==='
    'w.cleanDone' = 'Ο καθαρισμός ολοκληρώθηκε.'
    'w.fatal' = 'ΣΦΑΛΜΑ: {0}'; 'w.file' = 'αρχείο'
    'btn.about' = 'Σχετικά'; 'tip.about' = 'Έκδοση, άδεια χρήσης και αναφορές'
    'about.title' = 'Σχετικά'; 'about.version' = 'Έκδοση {0}'
    'about.desc' = 'Καθαρισμός Windows για developers: caches εργαλείων ανάπτυξης, φάκελοι build, προσωρινά αρχεία και μεγάλα αρχεία, σε ένα παράθυρο.'
    'about.hLicense' = 'Άδεια χρήσης'
    'about.copyright' = '© 2026 Kwstas (kwstas147). Ο κώδικας διατίθεται με την άδεια MIT.'
    'about.hCredits' = 'Αναφορές'
    'about.icon' = 'Εικονίδιο: «Cleaner brom» από τα Funline Icons (icon-icons.com), με άδεια CC BY 4.0. Το εικονίδιο της εφαρμογής είναι προσαρμογή του.'
    'about.hDisclaimer' = 'Αποποίηση ευθύνης'
    'about.disclaimer' = 'Το λογισμικό παρέχεται «ως έχει», χωρίς καμία εγγύηση. Διαγράφει αρχεία με δικαιώματα Διαχειριστή και η χρήση του γίνεται με δική σας ευθύνη. Δεν σχετίζεται με τη Microsoft, τη Google, τη JetBrains ή άλλη εταιρεία που αναφέρεται. Τα ονόματα προϊόντων ανήκουν στους κατόχους τους.'
    'about.repo' = 'Κώδικας στο GitHub'; 'about.iconPage' = 'Σελίδα εικονιδίου'; 'about.ccby' = 'Άδεια CC BY 4.0'
    'about.license' = 'Άδεια MIT...'; 'about.close' = 'Κλείσιμο'; 'about.licenseTitle' = 'Άδεια χρήσης (MIT)'
  }
  en = @{
    'grp.win' = 'Windows'; 'grp.ide' = 'IDEs & code editors'; 'grp.dev' = 'Developer tools'
    'grp.web' = 'Browsers'; 'grp.app' = 'Apps'; 'grp.custom' = 'My folders'
    'lang.button' = 'Ελληνικά'
    'theme.toDark' = '☾  Dark theme'; 'theme.toLight' = '☀  Light theme'
    'nav.clean' = 'Clean up'; 'nav.big' = 'Large files & node_modules'; 'nav.hist' = 'History'
    'btn.stop' = 'Stop'; 'btn.log' = 'Log file'; 'btn.all' = 'All'; 'btn.none' = 'None'
    'btn.defaults' = 'Defaults'; 'btn.addDir' = '+ Folder...'; 'btn.delDir' = 'Remove folder'
    'btn.clean' = 'Clean now'; 'btn.scan' = 'Scan sizes'
    'btn.findBig' = 'Find large files'; 'btn.findDev' = 'Find node_modules / venv'
    'btn.delSel' = 'Delete selected'; 'btn.openLoc' = 'Open location'; 'btn.histClear' = 'Clear history'
    'box.desc' = 'Description'; 'box.opt' = 'Settings'; 'box.log' = 'Log'
    'opt.projects' = 'Projects folder:'; 'opt.kill' = 'Apps to close:'
    'status.ready' = 'Ready.'
    'desc.initial' = 'Select a task to see exactly what it cleans and which of its folders exist on this PC.'
    'lbl.searchIn' = 'Search in:'; 'lbl.minSize' = 'Minimum size (MB):'
    'big.hint' = 'Tick what you want to delete. Double-click = show in Explorer. Click a column = sort.'
    'chk.recycle' = 'Files to Recycle Bin (safer)'
    'big.selected' = 'Selected: {0}  -  {1}'
    'col.path' = 'Path'; 'col.size' = 'Size'; 'col.modified' = 'Last modified'; 'col.type' = 'Type'
    'col.date' = 'Date'; 'col.freed' = 'Freed'; 'col.freeAfter' = 'Free space after'
    'col.duration' = 'Duration'; 'col.tasks' = 'Tasks'; 'col.note' = 'Note'
    'tip.kill' = '.exe names separated by space, comma or semicolon'
    'tip.scan' = 'Calculates how much space each category takes (deletes nothing)'
    'tip.findDev' = 'Finds node_modules, venv/.venv, __pycache__, .next, .nuxt, .turbo, .parcel-cache, .angular. They are recreated by npm install / pip install.'
    'tip.recycle' = 'Files go to the Recycle Bin. node_modules / venv folders are always deleted permanently (thousands of small files).'
    'tip.lang' = 'Αλλαγή σε Ελληνικά'
    'total.known' = 'Selected: {0}  -  estimated space: {1}'
    'total.unknown' = 'Selected: {0}  (press "Scan sizes" for an estimate)'
    'free.header' = 'Free space {0}  {1}     |     Log file: {2}'
    'desc.group' = 'Group "{0}". Tick the group to select all of its tasks.'
    'desc.custom' = 'Your own folder: ALL of its contents are deleted PERMANENTLY (not to the Recycle Bin). The folder itself is kept.'
    'desc.wsl' = 'Virtual disks found ({0}):'
    'desc.found' = 'Folders found ({0} of {1}):'
    'desc.more' = '  ... and {0} more'
    'desc.none' = '  (none - nothing to clean)'
    'done.summary' = "Freed: {0}`nFree space now: {1}`nTime: {2}"
    'done.cleanOk' = 'Clean-up finished.'; 'done.cleanCancel' = 'Clean-up was stopped.'
    'done.delete' = 'Deletion finished - freed {0}.'
    'done.found' = '{0} results found.'
    'hist.sum' = 'Freed {0} in total over {1} clean-ups  -  average {2}'
    'hist.empty' = 'No history yet. Each clean-up will appear here.'
    'hist.cancelled' = 'Stopped'
    'hist.clearConfirm' = 'Delete the whole clean-up history?'; 'hist.title' = 'History'
    'chart.title' = 'Space freed per clean-up (last 20)'
    'chart.empty' = 'No history yet - run a clean-up.'
    'chart.tip' = "{0}`nFreed: {1}`nFree space after: {2}`nDuration: {3}`nTasks: {4}"
    'msg.protected' = "This folder is protected and cannot be added:`n{0}"; 'msg.protectedTitle' = 'Protection'
    'msg.addDir' = "While ticked, ALL contents of this folder will be deleted permanently:`n`n{0}`n`nAdd it?"
    'msg.addDirTitle' = 'New folder'
    'dlg.addDir' = 'Choose a folder whose contents will be emptied'
    'dlg.projects' = 'Folder containing your Flutter / Android projects'
    'dlg.root' = 'Where should the search run?'
    'msg.selectCustom' = 'First select a folder from the "My folders" group.'
    'msg.noTasks' = 'No task is selected.'
    'msg.rootMissing' = 'The search folder does not exist.'
    'msg.checkFirst' = 'First tick the items you want to delete.'
    'msg.busy' = 'A task is running. Press "Stop" and wait for the current step to finish.'
    'confirm.tasks' = "The following tasks will run:`n`n{0}`n{1}`n`nContinue?"; 'confirm.title' = 'Confirm'
    'warn.kill' = '⚠ The listed apps will be closed WITHOUT saving.'
    'warn.dism' = '⚠ DISM takes 10-20 minutes.'
    'warn.wsl' = '⚠ WSL will be shut down. Quit Docker Desktop first.'
    'warn.winold' = '⚠ After deleting Windows.old you cannot roll back to the previous Windows version.'
    'warn.custom' = '⚠ The contents of your own folders are deleted permanently.'
    'warn.browsers' = '⚠ Close your browsers before continuing.'
    'del.files' = '•  {0} files -> {1}'; 'del.toBin' = 'to the Recycle Bin'; 'del.permanent' = 'PERMANENT deletion'
    'del.dirs' = '•  {0} folders -> PERMANENT deletion (recreated by npm install / pip install)'
    'del.confirm' = "{0} items ({1}) will be deleted:`n{2}`n`nContinue?"; 'del.title' = 'Confirm deletion'
    'log.scanAll' = 'Scanning the size of all categories...'
    'log.searchIn' = 'Searching in {0}...'
    'log.stop' = 'Stop requested - will stop after the current step...'
    'log.ready' = 'Ready. Tick what you want cleaned and press "Clean now".'
    'status.scanning' = 'Scanning... (a whole drive can take 1-3 minutes)'
    'w.protected' = '  SAFETY: skipped {0}'; 'w.empty' = '  Emptying: {0}'; 'w.delete' = '  Deleting: {0}'
    'w.noWsl' = '  No WSL / Docker disks found.'
    'w.compress' = '  Compacting: {0} ({1})'; 'w.compressed' = '    -> {0} (saved {1})'
    'w.cleanmgr' = '  Running cleanmgr /sagerun:{0} (it may open its own window)...'
    'w.cleanmgrExit' = '  cleanmgr: exit code {0}'
    'w.dism' = '  DISM /StartComponentCleanup - please wait, 10-20 minutes...'
    'w.dismCode' = '  WARNING: DISM returned code {0}'
    'w.killed' = '  Closed: {0}'; 'w.notRunning' = '  Not running: {0}'
    'w.noWinOld' = '  There is no Windows.old folder.'
    'w.svcStop' = '  Stopping services wuauserv, bits'; 'w.svcStart' = '  Services restarted'
    'w.scanProgress' = 'Scanning: {0} folders, {1} files - {2}'
    'w.bigFound' = 'Found {0} files >= {1} in {2} folders (showing the {3} largest).'
    'w.devProgress' = 'Scanning: {0} folders, found {1} - {2}'
    'w.devFound' = 'Found {0} development folders, {1} in total.'
    'w.toBin' = '  To Recycle Bin: {0}'; 'w.error' = '  ERROR: {0}'
    'w.scanItem' = 'Scanning: {0}'; 'w.scanDone' = 'Scan finished.'
    'w.start' = '=== CLEAN-UP START - Free space {0} {1} ==='
    'w.cancelled' = 'Stopped by the user.'
    'w.end' = '=== END - Time {0} - Freed {1} - Free space {2} ==='
    'w.cleanDone' = 'Clean-up finished.'
    'w.fatal' = 'ERROR: {0}'; 'w.file' = 'file'
    'btn.about' = 'About'; 'tip.about' = 'Version, license and credits'
    'about.title' = 'About'; 'about.version' = 'Version {0}'
    'about.desc' = 'A Windows clean-up tool for developers: developer tool caches, build folders, temporary files and large files, in one window.'
    'about.hLicense' = 'License'
    'about.copyright' = '© 2026 Kwstas (kwstas147). The source code is released under the MIT License.'
    'about.hCredits' = 'Credits'
    'about.icon' = 'Icon: "Cleaner brom" by Funline Icons (icon-icons.com), licensed under CC BY 4.0. The application icon is adapted from it.'
    'about.hDisclaimer' = 'Disclaimer'
    'about.disclaimer' = 'This software is provided "as is", without warranty of any kind. It deletes files with Administrator rights and you use it at your own risk. It is not affiliated with Microsoft, Google, JetBrains or any other company mentioned. Product names belong to their owners.'
    'about.repo' = 'Source code on GitHub'; 'about.iconPage' = 'Icon page'; 'about.ccby' = 'CC BY 4.0 license'
    'about.license' = 'MIT License...'; 'about.close' = 'Close'; 'about.licenseTitle' = 'License (MIT)'
  }
}

function L([string]$k) {
    $t = $Str[$sync.Lang][$k]
    if ($null -eq $t) { $t = $Str['en'][$k] }
    if ($null -eq $t) { return $k }
    if ($args.Count -gt 0) { return ($t -f $args) }
    return $t
}
'@

# ============================================================
#  ΠΥΡΗΝΑΣ - εκτελείται στο παρασκήνιο (ξεχωριστό runspace)
#  ώστε το παράθυρο να μην "παγώνει".
# ============================================================
$WorkerCore = @'
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName Microsoft.VisualBasic

function Send-Msg($type, $data) { $sync.Queue.Enqueue([pscustomobject]@{ T = $type; D = $data }) }

function Write-Log([string]$m) {
    Send-Msg 'log' $m
    try {
        Add-Content -LiteralPath $sync.LogPath -Encoding UTF8 -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
    } catch { }
}

function Format-Size([double]$b) {
    if ($b -ge 1GB) { '{0:N2} GB' -f ($b / 1GB) }
    elseif ($b -ge 1MB) { '{0:N1} MB' -f ($b / 1MB) }
    elseif ($b -ge 1KB) { '{0:N0} KB' -f ($b / 1KB) }
    else { '{0:N0} B' -f $b }
}

function Get-FreeBytes {
    try { (New-Object System.IO.DriveInfo $env:SystemDrive).AvailableFreeSpace } catch { [int64]0 }
}

# --- Δικλείδα ασφαλείας: ΠΟΤΕ CrossDevice, ρίζες δίσκων ή βασικοί φάκελοι ---
function Test-Protected([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $true }
    if ($p -match 'CrossDevice') { return $true }
    try { $full = [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return $true }
    if ($full.Length -le 3) { return $true }
    $blocked = @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
                 $env:USERPROFILE, (Join-Path $env:SystemDrive 'Users'), $env:APPDATA, $env:LOCALAPPDATA) |
               Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    foreach ($b in $blocked) { if ($full -ieq $b) { return $true } }
    return $false
}

function Test-UnderSystem([string]$p) {
    try { $full = [IO.Path]::GetFullPath($p).TrimEnd('\') + '\' } catch { return $true }
    foreach ($b in @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($b -and $full.StartsWith($b.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# Επιπλέον έλεγχος για φακέλους που προσθέτει ο χρήστης
function Test-CustomBlocked([string]$p) { (Test-Protected $p) -or (Test-UnderSystem $p) }

# --- Αδειάζει τα περιεχόμενα φακέλου (robocopy /MIR, 32 νήματα, παρακάμπτει το όριο 260 χαρ.) ---
function Clear-Contents([string]$p, [switch]$Quiet) {
    if (-not (Test-Path -LiteralPath $p)) { return }
    if (Test-Protected $p) { Write-Log (L 'w.protected' $p); return }
    if (-not $Quiet) { Write-Log (L 'w.empty' $p) }
    if (-not (Test-Path -LiteralPath $sync.EmptyDir)) { New-Item -ItemType Directory -Path $sync.EmptyDir -Force | Out-Null }
    & robocopy.exe $sync.EmptyDir $p /MIR /XJ /NFL /NDL /NJH /NJS /NC /NS /NP /MT:32 /R:0 /W:0 2>&1 | Out-Null
}

# --- Διαγράφει ολόκληρο τον φάκελο (ή αρχείο) ---
function Remove-Fast([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return }
    if (Test-Protected $p) { Write-Log (L 'w.protected' $p); return }
    Write-Log (L 'w.delete' $p)
    $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; return }
    Clear-Contents $p -Quiet
    & cmd.exe /d /c "rd /s /q `"$p`"" 2>&1 | Out-Null
}

# --- Μέγεθος φακέλου (χωρίς να ακολουθεί junctions) ---
function Get-DirSize([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $it = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($it -and -not $it.PSIsContainer) { return [int64]$it.Length }
    $total = [int64]0
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        if ($sync.Cancel) { break }
        $d = $stack.Pop()
        try {
            $di = New-Object System.IO.DirectoryInfo -ArgumentList $d
            foreach ($f in $di.GetFiles()) { $total += $f.Length }
            foreach ($s in $di.GetDirectories()) {
                if (($s.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push($s.FullName) }
            }
        } catch { }
    }
    return $total
}

# --- Παλιές εκδόσεις Android Studio: κρατά μόνο τη νεότερη ---
function Get-OldAndroidStudio {
    $res = @()
    foreach ($b in @((Join-Path $env:LOCALAPPDATA 'Google'), (Join-Path $env:APPDATA 'Google'))) {
        if (-not (Test-Path -LiteralPath $b)) { continue }
        $items = @(Get-ChildItem -LiteralPath $b -Directory -Filter 'AndroidStudio*' -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $v = $null
            if ([version]::TryParse(($_.Name -replace '^AndroidStudio', ''), [ref]$v)) {
                [pscustomobject]@{ Path = $_.FullName; Ver = $v }
            }
        })
        if ($items.Count -gt 1) {
            $newest = ($items | Sort-Object Ver -Descending)[0]
            $res += @($items | Where-Object { $_.Path -ne $newest.Path } | ForEach-Object { $_.Path })
        }
    }
    $res
}

# --- Caches εφαρμογών Chromium / WebView2 (Chrome, Edge, νέο Teams) ---
function Get-ChromiumCachePaths([string]$ud) {
    if (-not (Test-Path -LiteralPath $ud)) { return }
    Join-Path $ud 'ShaderCache'
    Join-Path $ud 'GrShaderCache'
    Get-ChildItem -LiteralPath $ud -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -like 'WV2Profile_*' } | ForEach-Object {
            foreach ($s in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') { Join-Path $_.FullName $s }
        }
}

# --- Εικονικοί δίσκοι WSL / Docker Desktop ---
function Get-WslVhdx {
    $L = $env:LOCALAPPDATA
    $r = @()
    if (Test-Path -LiteralPath "$L\Packages") {
        $r += @(Get-ChildItem -Path "$L\Packages\*\LocalState\ext4.vhdx" -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
    foreach ($d in "$L\wsl", "$L\Docker\wsl") {
        if (Test-Path -LiteralPath $d) {
            $r += @(Get-ChildItem -LiteralPath $d -Recurse -Filter '*.vhdx' -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }
    $r | Select-Object -Unique
}

# --- Ποιοι φάκελοι αντιστοιχούν σε κάθε εργασία ---
function Get-TaskPaths([string]$id) {
    $A = $env:APPDATA; $L = $env:LOCALAPPDATA; $U = $env:USERPROFILE
    $ideSub = 'Cache', 'GPUCache', 'CachedData', 'Code Cache', 'WebStorage', 'Crashpad', 'CachedExtensionVSIXs'
    $r = @(switch -Wildcard ($id) {
        'cursor'        { $ideSub | ForEach-Object { Join-Path "$A\Cursor" $_ } }
        'vscode'        { $ideSub | ForEach-Object { Join-Path "$A\Code" $_ } }
        'antigravity'   { "$L\antigravity\Cache", "$A\Antigravity\Cache", "$A\Antigravity IDE\Cache", "$L\hermes\cache" }
        'jetbrains'     {
            if (Test-Path -LiteralPath "$L\JetBrains") {
                Get-ChildItem -LiteralPath "$L\JetBrains" -Directory -Force -ErrorAction SilentlyContinue |
                    ForEach-Object { Join-Path $_.FullName 'caches' }
            }
        }
        'oldstudio'     { Get-OldAndroidStudio }
        'dart'          { "$L\.dartServer" }
        'arduino'       { "$L\Arduino15\staging" }
        'androidmodels' { "$U\.android\models" }
        'gradle'        {
            $g = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { "$U\.gradle" }
            '.tmp', 'daemon', 'caches', 'wrapper\dists' | ForEach-Object { Join-Path $g $_ }
        }
        'flutter'       {
            $root = $sync.ProjectsRoot
            if ($root -and (Test-Path -LiteralPath $root)) {
                Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $pr = $_.FullName
                    'build', '.dart_tool', '.gradle', 'android\.gradle', 'android\build', 'android\app\build',
                    'app\build', 'app\caches', 'app\jdks', 'app\wrapper' | ForEach-Object { Join-Path $pr $_ }
                }
            }
        }
        'npm'           { "$L\npm-cache", "$L\pnpm-cache" }
        'yarn'          { "$L\Yarn\Cache", "$L\Yarn\Berry\cache" }
        'pip'           { "$L\pip\cache" }
        'nuget'         { "$U\.nuget\packages", "$L\NuGet\v3-cache", "$L\NuGet\plugins-cache", "$env:TEMP\NuGetScratch" }
        'pubcache'      { if ($env:PUB_CACHE) { $env:PUB_CACHE } else { "$L\Pub\Cache" } }
        'chrome'        { Get-ChromiumCachePaths "$L\Google\Chrome\User Data" }
        'edge'          { Get-ChromiumCachePaths "$L\Microsoft\Edge\User Data" }
        'discord'       {
            foreach ($d in 'discord', 'discordptb', 'discordcanary') {
                foreach ($s in 'Cache', 'Code Cache', 'GPUCache') { "$A\$d\$s" }
            }
        }
        'spotify'       { "$L\Spotify\Data", "$L\Packages\SpotifyAB.SpotifyMusic_zpdnekdrzrea0\LocalCache\Spotify\Data" }
        'teams'         {
            foreach ($s in 'Cache', 'Code Cache', 'GPUCache', 'blob_storage', 'tmp') { "$A\Microsoft\Teams\$s" }
            Get-ChromiumCachePaths "$L\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView"
        }
        'winupdate'     { "$env:SystemRoot\SoftwareDistribution\Download" }
        'usertemp'      { $env:TEMP }
        'systemtemp'    { "$env:SystemRoot\Temp" }
        'recycle'       { Join-Path $env:SystemDrive '$Recycle.Bin' }
        'windowsold'    { Join-Path $env:SystemDrive 'Windows.old' }
        'prefetch'      { "$env:SystemRoot\Prefetch" }
        'crashdumps'    {
            "$L\CrashDumps", "$env:SystemRoot\Minidump", "$env:SystemRoot\MEMORY.DMP",
            "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
            "$L\Microsoft\Windows\WER\ReportArchive", "$L\Microsoft\Windows\WER\ReportQueue"
        }
        'custom:*'      { $id.Substring(7) }
    })
    @($r | Where-Object { $_ })
}

function Remove-TaskPaths([string]$id) {
    foreach ($p in (Get-TaskPaths $id)) {
        if ($sync.Cancel) { return }
        Remove-Fast $p
    }
}

# --- cleanmgr με συγκεκριμένο προφίλ (sagerun) και λίστα handlers ---
function Invoke-CleanMgrProfile([int]$num, [string[]]$handlers) {
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $flag = 'StateFlags{0:D4}' -f $num
    Get-ChildItem -Path $base -ErrorAction SilentlyContinue | ForEach-Object {
        Set-ItemProperty -LiteralPath $_.PSPath -Name $flag -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    foreach ($k in $handlers) {
        $p = Join-Path $base $k
        if (Test-Path -LiteralPath $p) { Set-ItemProperty -LiteralPath $p -Name $flag -Value 2 -Type DWord -ErrorAction SilentlyContinue }
    }
    Write-Log (L 'w.cleanmgr' $num)
    $pr = Start-Process cleanmgr.exe -ArgumentList "/sagerun:$num" -Wait -PassThru
    Write-Log (L 'w.cleanmgrExit' $pr.ExitCode)
}

function Invoke-Dism {
    Write-Log (L 'w.dism')
    $out = & dism.exe /online /cleanup-image /startcomponentcleanup 2>&1
    $code = $LASTEXITCODE
    $out | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '%' -and $_ -notmatch '^\[' } |
        Select-Object -Last 4 | ForEach-Object { Write-Log "  $_" }
    if ($code -ne 0) { Write-Log (L 'w.dismCode' $code) }
}

function Invoke-WslCompact {
    $files = @(Get-WslVhdx)
    if ($files.Count -eq 0) { Write-Log (L 'w.noWsl'); return }
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        Write-Log '  wsl --shutdown'
        & wsl.exe --shutdown 2>&1 | Out-Null
        Start-Sleep -Seconds 3
    }
    $fso = New-Object -ComObject Scripting.FileSystemObject
    foreach ($f in $files) {
        if ($sync.Cancel) { return }
        $before = (Get-Item -LiteralPath $f -Force).Length
        # Το diskpart διαβάζει το script σε ASCII: για ελληνικά ονόματα χρησιμοποιείται η σύντομη (8.3) διαδρομή
        $dp = $f
        if ($dp -match '[^\x00-\x7F]') { try { $dp = $fso.GetFile($f).ShortPath } catch { } }
        $dpFile = Join-Path $env:TEMP 'sysopt_diskpart.txt'
        Set-Content -LiteralPath $dpFile -Encoding ASCII -Value @(
            "select vdisk file=`"$dp`"", 'attach vdisk readonly', 'compact vdisk', 'detach vdisk')
        Write-Log (L 'w.compress' $f (Format-Size $before))
        & diskpart.exe /s $dpFile 2>&1 | Out-Null
        Remove-Item -LiteralPath $dpFile -Force -ErrorAction SilentlyContinue
        $after = (Get-Item -LiteralPath $f -Force).Length
        Write-Log (L 'w.compressed' (Format-Size $after) (Format-Size ([math]::Max(0, $before - $after))))
    }
}

function Stop-Apps {
    $names = @($sync.KillList -split '[\s,;]+' | Where-Object { $_ })
    foreach ($n in $names) {
        $exe = if ($n -like '*.exe') { $n } else { "$n.exe" }
        if (Get-Process -Name ($exe -replace '\.exe$', '') -ErrorAction SilentlyContinue) {
            & taskkill.exe /F /IM $exe /T 2>&1 | Out-Null
            Write-Log (L 'w.killed' $exe)
        } else {
            Write-Log (L 'w.notRunning' $exe)
        }
    }
}

function Invoke-Tool([string]$cmd, [string[]]$toolArgs) {
    $c = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($c) { Write-Log "  $cmd $($toolArgs -join ' ')"; & $c.Source @toolArgs 2>&1 | Out-Null }
}

function Invoke-Task([string]$id) {
    switch -Wildcard ($id) {
        'cleanmgr'   {
            Invoke-CleanMgrProfile 65535 @('Active Setup Temp Folders', 'D3D Shader Cache', 'Update Cleanup',
                'Windows Upgrade Log Files', 'Delivery Optimization Files', 'Thumbnail Cache', 'Windows Defender',
                'Internet Temporary Files', 'DirectX Shader Cache', 'Setup Log Files', 'Temporary Files', 'Device Driver Packages')
            break
        }
        'windowsold' {
            if (Test-Path -LiteralPath "$env:SystemDrive\Windows.old") { Invoke-CleanMgrProfile 65534 @('Previous Installations') }
            else { Write-Log (L 'w.noWinOld') }
            break
        }
        'winupdate'  {
            Write-Log (L 'w.svcStop')
            Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
            Clear-Contents "$env:SystemRoot\SoftwareDistribution\Download"
            Start-Service -Name wuauserv, bits -ErrorAction SilentlyContinue
            Write-Log (L 'w.svcStart')
            break
        }
        'usertemp'   { Clear-Contents $env:TEMP; break }
        'systemtemp' { Clear-Contents "$env:SystemRoot\Temp"; break }
        'prefetch'   { Clear-Contents "$env:SystemRoot\Prefetch"; break }
        'recycle'    { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; break }
        'dns'        { & ipconfig.exe /flushdns 2>&1 | Out-Null; break }
        'dism'       { Invoke-Dism; break }
        'wsl'        { Invoke-WslCompact; break }
        'eventlogs'  {
            foreach ($l in 'System', 'Application') { & wevtutil.exe cl $l 2>&1 | Out-Null; Write-Log "  Event log: $l" }
            break
        }
        'killapps'   { Stop-Apps; break }
        'npm'        { Remove-TaskPaths $id; Invoke-Tool 'npm.cmd' @('cache', 'clean', '--force'); break }
        'yarn'       { Remove-TaskPaths $id; Invoke-Tool 'yarn.cmd' @('cache', 'clean'); break }
        'pip'        { Remove-TaskPaths $id; Invoke-Tool 'pip.exe' @('cache', 'purge'); break }
        'nuget'      { Invoke-Tool 'dotnet.exe' @('nuget', 'locals', 'all', '--clear'); Remove-TaskPaths $id; break }
        'custom:*'   { Clear-Contents $id.Substring(7); break }
        default      { Remove-TaskPaths $id }
    }
}

# --- Αναζήτηση μεγάλων αρχείων ---
function Find-LargeFiles {
    $min = [int64]$sync.MinBytes
    $found = New-Object 'System.Collections.Generic.List[object]'
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($sync.ScanRoot)
    $dirs = 0
    $hs = [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
    $noExt = L 'w.file'
    while ($stack.Count -gt 0) {
        if ($sync.Cancel) { break }
        $d = $stack.Pop(); $dirs++
        if ($dirs % 300 -eq 0) { Send-Msg 'progress' @{ V = 0; Max = 0; Text = (L 'w.scanProgress' $dirs $found.Count $d) } }
        try {
            $di = New-Object System.IO.DirectoryInfo -ArgumentList $d
            foreach ($f in $di.GetFiles()) {
                if ($f.Length -ge $min -and (($f.Attributes -band $hs) -ne $hs)) {
                    $found.Add([pscustomobject]@{ Path = $f.FullName; Bytes = $f.Length; Modified = $f.LastWriteTime
                                                  Kind = $(if ($f.Extension) { $f.Extension.ToLower() } else { $noExt }); IsDir = $false })
                }
            }
            foreach ($s in $di.GetDirectories()) {
                if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $n = $s.Name
                if ($n -eq 'System Volume Information' -or $n -eq '$Recycle.Bin' -or $n -match 'CrossDevice') { continue }
                if ($s.FullName -ieq $env:SystemRoot) { continue }
                $stack.Push($s.FullName)
            }
        } catch { }
    }
    $top = @($found | Sort-Object Bytes -Descending | Select-Object -First 300)
    Write-Log (L 'w.bigFound' $found.Count (Format-Size $min) $dirs $top.Count)
    Send-Msg 'found' $top
}

# --- Αναζήτηση node_modules / venv / caches μέσα σε projects ---
function Find-DevDirs {
    $names = 'node_modules', '.venv', 'venv', '__pycache__', '.next', '.nuxt', '.turbo', '.parcel-cache', '.angular'
    $skip = @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, "$env:APPDATA\npm") |
            Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') + '\' }
    $found = New-Object 'System.Collections.Generic.List[object]'
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($sync.ScanRoot)
    $dirs = 0
    while ($stack.Count -gt 0) {
        if ($sync.Cancel) { break }
        $d = $stack.Pop(); $dirs++
        if ($dirs % 300 -eq 0) { Send-Msg 'progress' @{ V = 0; Max = 0; Text = (L 'w.devProgress' $dirs $found.Count $d) } }
        try {
            $di = New-Object System.IO.DirectoryInfo -ArgumentList $d
            foreach ($s in $di.GetDirectories()) {
                if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $n = $s.Name
                if ($n -eq 'System Volume Information' -or $n -eq '$Recycle.Bin' -or $n -match 'CrossDevice') { continue }
                $full = $s.FullName + '\'
                $skipIt = $false
                foreach ($k in $skip) { if ($full.StartsWith($k, [StringComparison]::OrdinalIgnoreCase)) { $skipIt = $true; break } }
                if ($skipIt) { continue }
                $isHit = $names -contains $n
                if ($isHit -and ($n -eq 'venv' -or $n -eq '.venv') -and -not (Test-Path -LiteralPath (Join-Path $s.FullName 'pyvenv.cfg'))) { $isHit = $false }
                if ($isHit) {
                    $found.Add([pscustomobject]@{ Path = $s.FullName; Bytes = (Get-DirSize $s.FullName); Modified = $s.LastWriteTime
                                                  Kind = $n; IsDir = $true })
                } else {
                    $stack.Push($s.FullName)
                }
            }
        } catch { }
    }
    $top = @($found | Sort-Object Bytes -Descending | Select-Object -First 500)
    $sum = [int64]0; foreach ($f in $found) { $sum += $f.Bytes }
    Write-Log (L 'w.devFound' $found.Count (Format-Size $sum))
    Send-Msg 'found' $top
}

# --- Διαγραφή επιλεγμένων από τη σελίδα «Μεγάλα αρχεία» ---
function Remove-SelectedItems {
    foreach ($it in @($sync.DeleteList)) {
        if ($sync.Cancel) { break }
        $p = $it.Path; $ok = $false
        if ((Test-Protected $p) -or (Test-UnderSystem $p)) {
            Write-Log (L 'w.protected' $p)
        } elseif ($it.IsDir) {
            Remove-Fast $p
            $ok = -not (Test-Path -LiteralPath $p)
        } else {
            try {
                if ($sync.UseRecycle) {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p,
                        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                    Write-Log (L 'w.toBin' $p)
                } else {
                    [IO.File]::Delete($p)
                    Write-Log (L 'w.delete' $p)
                }
            } catch { Write-Log (L 'w.error' "$p - $($_.Exception.Message)") }
            $ok = -not (Test-Path -LiteralPath $p)
        }
        Send-Msg 'deleted' @{ Path = $p; Ok = $ok }
    }
}

function Start-Main {
    $ids = @($sync.Items)
    $n = $ids.Count
    try {
        switch ($sync.Mode) {
            'bigfiles' { Find-LargeFiles; Send-Msg 'done' @{ Mode = 'bigfiles' }; return }
            'devdirs'  { Find-DevDirs; Send-Msg 'done' @{ Mode = 'devdirs' }; return }
            'delete'   {
                $f0 = Get-FreeBytes
                Remove-SelectedItems
                Send-Msg 'done' @{ Mode = 'delete'; Freed = [math]::Max([int64]0, [int64]((Get-FreeBytes) - $f0)) }
                return
            }
        }

        if ($sync.Mode -eq 'scan') {
            for ($i = 0; $i -lt $n; $i++) {
                if ($sync.Cancel) { break }
                $id = $ids[$i]
                Send-Msg 'progress' @{ V = $i; Max = $n; Text = (L 'w.scanItem' $sync.Names[$id]) }
                $paths = @(Get-TaskPaths $id)
                $bytes = [int64]-1
                if ($paths.Count -gt 0) { $bytes = [int64]0; foreach ($p in $paths) { $bytes += Get-DirSize $p } }
                Send-Msg 'size' @{ Id = $id; Bytes = $bytes }
            }
            Send-Msg 'progress' @{ V = $n; Max = $n; Text = (L 'w.scanDone') }
            Send-Msg 'done' @{ Mode = 'scan' }
            return
        }

        # Σειρά: πρώτα τερματισμός εφαρμογών (ξεκλειδώνει αρχεία), αργές εργασίες στο τέλος
        $slow = 'wsl', 'dism'
        $ids = @($ids | Where-Object { $_ -eq 'killapps' }) +
               @($ids | Where-Object { $_ -ne 'killapps' -and $slow -notcontains $_ }) +
               @($slow | Where-Object { $ids -contains $_ })

        $free0 = Get-FreeBytes
        $t0 = Get-Date
        Write-Log (L 'w.start' $env:SystemDrive (Format-Size $free0))
        $cancelled = $false
        for ($i = 0; $i -lt $n; $i++) {
            if ($sync.Cancel) { $cancelled = $true; Write-Log (L 'w.cancelled'); break }
            $id = $ids[$i]
            $name = $sync.Names[$id]; if (-not $name) { $name = $id }
            Send-Msg 'progress' @{ V = $i; Max = $n; Text = "[$($i + 1)/$n] $name" }
            Write-Log "> $name"
            try { Invoke-Task $id } catch { Write-Log (L 'w.error' $_.Exception.Message) }
            Send-Msg 'taskdone' $id
        }
        $free1 = Get-FreeBytes
        $elapsed = (Get-Date) - $t0
        $freed = [math]::Max([int64]0, [int64]($free1 - $free0))
        Write-Log (L 'w.end' ('{0:hh\:mm\:ss}' -f $elapsed) (Format-Size $freed) (Format-Size $free1))
        Send-Msg 'progress' @{ V = $n; Max = $n; Text = (L 'w.cleanDone') }
        Send-Msg 'done' @{ Mode = 'clean'; Freed = $freed; Free = $free1; Elapsed = $elapsed; Cancelled = $cancelled; Tasks = $n }
    } catch {
        Write-Log (L 'w.fatal' $_.Exception.Message)
        Send-Msg 'done' @{ Mode = $sync.Mode; Error = $true }
    }
}
'@

# Φόρτωση κειμένων και βοηθητικών συναρτήσεων και στο UI
. ([scriptblock]::Create($LangCore))
. ([scriptblock]::Create($WorkerCore))

# ============================================================
#  ΟΡΙΣΜΟΣ ΕΡΓΑΣΙΩΝ (ό,τι εμφανίζεται ως κουτάκι)
#  Id, ομάδα, προεπιλογή, όνομα/περιγραφή σε el και en
# ============================================================
$GroupKeys = 'win', 'ide', 'dev', 'web', 'app', 'custom'

function T($id, $group, $default, $nameEl, $descEl, $nameEn, $descEn) {
    [pscustomobject]@{ Id = $id; Group = $group; Default = $default
                       Name = @{ el = $nameEl; en = $nameEn }; Desc = @{ el = $descEl; en = $descEn } }
}

$TaskMeta = @(
    T 'cleanmgr' 'win' $true `
        'Εκκαθάριση Δίσκου Windows (cleanmgr)' 'Εκτελεί την Εκκαθάριση Δίσκου των Windows (cleanmgr /sagerun) για: προσωρινά αρχεία, Windows Update Cleanup, αρχεία καταγραφής εγκατάστασης/αναβάθμισης, Delivery Optimization, μικρογραφίες, DirectX shader cache, παλιά πακέτα οδηγών κ.ά. Ο Κάδος Ανακύκλωσης και το Windows.old ΔΕΝ περιλαμβάνονται εδώ (έχουν δικές τους επιλογές).' `
        'Windows Disk Cleanup (cleanmgr)' 'Runs Windows Disk Cleanup (cleanmgr /sagerun) for: temporary files, Windows Update Cleanup, setup/upgrade logs, Delivery Optimization, thumbnails, DirectX shader cache, old driver packages and more. The Recycle Bin and Windows.old are NOT included here (they have their own options).'
    T 'winupdate' 'win' $true `
        'Cache Windows Update' 'Σταματά τις υπηρεσίες wuauserv και BITS, αδειάζει το SoftwareDistribution\Download και τις ξεκινά ξανά. Τα Windows θα ξανακατεβάσουν ό,τι χρειαστούν.' `
        'Windows Update cache' 'Stops the wuauserv and BITS services, empties SoftwareDistribution\Download and starts them again. Windows will re-download whatever it needs.'
    T 'usertemp' 'win' $true `
        'Προσωρινά αρχεία χρήστη (%TEMP%)' 'Αδειάζει τον φάκελο %TEMP% του χρήστη. Αρχεία που χρησιμοποιούνται αυτή τη στιγμή παραλείπονται αυτόματα.' `
        'User temporary files (%TEMP%)' 'Empties the user %TEMP% folder. Files currently in use are skipped automatically.'
    T 'systemtemp' 'win' $true `
        'Προσωρινά αρχεία συστήματος (Windows\Temp)' 'Αδειάζει τον φάκελο C:\Windows\Temp.' `
        'System temporary files (Windows\Temp)' 'Empties C:\Windows\Temp.'
    T 'recycle' 'win' $true `
        'Κάδος Ανακύκλωσης' 'Αδειάζει ΟΡΙΣΤΙΚΑ τον Κάδο Ανακύκλωσης σε όλους τους δίσκους.' `
        'Recycle Bin' 'PERMANENTLY empties the Recycle Bin on all drives.'
    T 'crashdumps' 'win' $true `
        'Crash dumps & αναφορές σφαλμάτων (WER)' 'Αρχεία που γράφονται όταν «κρασάρει» μια εφαρμογή ή τα Windows: CrashDumps, Minidump, MEMORY.DMP και οι αναφορές του Windows Error Reporting. Χρειάζονται μόνο αν ψάχνετε την αιτία ενός σφάλματος.' `
        'Crash dumps & error reports (WER)' 'Files written when an app or Windows crashes: CrashDumps, Minidump, MEMORY.DMP and Windows Error Reporting reports. Only needed if you are investigating a crash.'
    T 'dns' 'win' $true `
        'Cache DNS (ipconfig /flushdns)' 'Καθαρίζει την cache DNS. Δεν ελευθερώνει χώρο - βοηθά σε προβλήματα σύνδεσης/ιστοσελίδων.' `
        'DNS cache (ipconfig /flushdns)' 'Clears the DNS cache. Frees no space - helps with connection/website problems.'
    T 'windowsold' 'win' $false `
        'Παλιά εγκατάσταση Windows (Windows.old)' 'Διαγράφει τον φάκελο Windows.old που μένει μετά από μεγάλη αναβάθμιση των Windows (συχνά 10-30 GB) μέσω της Εκκαθάρισης Δίσκου. ΠΡΟΣΟΧΗ: μετά δεν μπορείτε να επιστρέψετε στην προηγούμενη έκδοση των Windows.' `
        'Previous Windows installation (Windows.old)' 'Deletes the Windows.old folder left after a major Windows upgrade (often 10-30 GB) through Disk Cleanup. WARNING: afterwards you cannot roll back to the previous Windows version.'
    T 'prefetch' 'win' $false `
        'Prefetch' 'Αδειάζει το C:\Windows\Prefetch. Ελευθερώνει λίγο χώρο· οι πρώτες εκκινήσεις εφαρμογών μετά θα είναι λίγο πιο αργές μέχρι να ξαναχτιστεί. Χρήσιμο κυρίως για αντιμετώπιση προβλημάτων.' `
        'Prefetch' 'Empties C:\Windows\Prefetch. Frees a little space; the first app launches afterwards are slightly slower until it is rebuilt. Mostly useful for troubleshooting.'
    T 'dism' 'win' $false `
        'DISM Component Cleanup (αργό, 10-20 λεπτά)' 'DISM /Online /Cleanup-Image /StartComponentCleanup: αφαιρεί παλιές εκδόσεις στοιχείων από το WinSxS. Διαρκεί 10-20 λεπτά και εκτελείται πάντα στο τέλος.' `
        'DISM Component Cleanup (slow, 10-20 min)' 'DISM /Online /Cleanup-Image /StartComponentCleanup: removes superseded component versions from WinSxS. Takes 10-20 minutes and always runs last.'
    T 'eventlogs' 'win' $false `
        'Αρχεία καταγραφής συμβάντων (System, Application)' 'Διαγράφει τα logs System και Application του Event Viewer. Χάνεται το ιστορικό σφαλμάτων.' `
        'Event logs (System, Application)' 'Clears the System and Application logs in Event Viewer. The error history is lost.'

    T 'cursor' 'ide' $true `
        'Cursor - caches' 'Cache, GPUCache, CachedData, Code Cache, WebStorage, Crashpad, CachedExtensionVSIXs του Cursor. Κλείστε το Cursor πριν τον καθαρισμό.' `
        'Cursor - caches' 'Cursor Cache, GPUCache, CachedData, Code Cache, WebStorage, Crashpad, CachedExtensionVSIXs. Close Cursor before cleaning.'
    T 'vscode' 'ide' $true `
        'VS Code - caches' 'Cache, GPUCache, CachedData, Code Cache, WebStorage, Crashpad, CachedExtensionVSIXs του VS Code. Κλείστε το VS Code πριν τον καθαρισμό.' `
        'VS Code - caches' 'VS Code Cache, GPUCache, CachedData, Code Cache, WebStorage, Crashpad, CachedExtensionVSIXs. Close VS Code before cleaning.'
    T 'antigravity' 'ide' $true `
        'Antigravity & Hermes - caches' 'Cache του Antigravity / Antigravity IDE και του Hermes.' `
        'Antigravity & Hermes - caches' 'Cache of Antigravity / Antigravity IDE and Hermes.'
    T 'jetbrains' 'ide' $true `
        'JetBrains IDEs - caches' 'Οι φάκελοι caches όλων των JetBrains IDE (IntelliJ, PyCharm, κ.λπ.). Ξαναδημιουργούνται με το επόμενο indexing.' `
        'JetBrains IDEs - caches' 'The caches folders of all JetBrains IDEs (IntelliJ, PyCharm, etc.). Rebuilt on the next indexing.'
    T 'oldstudio' 'ide' $true `
        'Παλιές εκδόσεις Android Studio' 'Ρυθμίσεις/caches παλαιότερων εκδόσεων Android Studio (AppData\Local και Roaming\Google\AndroidStudio*). Κρατά αυτόματα ΜΟΝΟ τη νεότερη έκδοση που βρίσκει.' `
        'Old Android Studio versions' 'Settings/caches of older Android Studio versions (AppData\Local and Roaming\Google\AndroidStudio*). Automatically keeps ONLY the newest version it finds.'
    T 'dart' 'ide' $true `
        'Dart Analysis Server (.dartServer)' 'Cache του Dart Analysis Server. Ξαναχτίζεται αυτόματα με το άνοιγμα του project.' `
        'Dart Analysis Server (.dartServer)' 'Dart Analysis Server cache. Rebuilt automatically when you open a project.'

    T 'flutter' 'dev' $true `
        'Flutter/Android projects - build αρχεία' 'Για κάθε project στον φάκελο projects (βλ. Ρυθμίσεις): build, .dart_tool, .gradle, android\.gradle, android\build, android\app\build, app\build, app\caches, app\jdks, app\wrapper. Ο πηγαίος κώδικας ΔΕΝ αγγίζεται.' `
        'Flutter/Android projects - build output' 'For every project in the projects folder (see Settings): build, .dart_tool, .gradle, android\.gradle, android\build, android\app\build, app\build, app\caches, app\jdks, app\wrapper. Source code is NOT touched.'
    T 'gradle' 'dev' $true `
        'Gradle - caches, daemons, wrappers' 'Gradle caches, daemon, .tmp και κατεβασμένες διανομές wrapper (%USERPROFILE%\.gradle ή GRADLE_USER_HOME). Το επόμενο build θα ξανακατεβάσει dependencies - θα αργήσει και θέλει internet.' `
        'Gradle - caches, daemons, wrappers' 'Gradle caches, daemon, .tmp and downloaded wrapper distributions (%USERPROFILE%\.gradle or GRADLE_USER_HOME). The next build re-downloads dependencies - slower and needs internet.'
    T 'npm' 'dev' $true `
        'npm / pnpm cache' 'Φάκελοι npm-cache, pnpm-cache και εντολή npm cache clean --force.' `
        'npm / pnpm cache' 'The npm-cache and pnpm-cache folders plus npm cache clean --force.'
    T 'yarn' 'dev' $true `
        'Yarn cache' 'Φάκελοι Yarn\Cache και Yarn\Berry\cache και εντολή yarn cache clean.' `
        'Yarn cache' 'The Yarn\Cache and Yarn\Berry\cache folders plus yarn cache clean.'
    T 'pip' 'dev' $true `
        'pip cache' 'Φάκελος pip\cache και εντολή pip cache purge.' `
        'pip cache' 'The pip\cache folder plus pip cache purge.'
    T 'nuget' 'dev' $false `
        'NuGet (.NET) packages & cache' 'Φάκελοι .nuget\packages, NuGet\v3-cache, plugins-cache, NuGetScratch και εντολή dotnet nuget locals all --clear. Το επόμενο build .NET θα ξανακατεβάσει τα πακέτα.' `
        'NuGet (.NET) packages & cache' 'The .nuget\packages, NuGet\v3-cache, plugins-cache and NuGetScratch folders plus dotnet nuget locals all --clear. The next .NET build re-downloads the packages.'
    T 'pubcache' 'dev' $false `
        'Flutter / Dart pub-cache' 'Ο φάκελος Pub\Cache (ή PUB_CACHE) με ΟΛΑ τα κατεβασμένα πακέτα Dart/Flutter. Μετά χρειάζεται «flutter pub get» σε κάθε project και διαγράφονται τα global εργαλεία (dart pub global).' `
        'Flutter / Dart pub-cache' 'The Pub\Cache folder (or PUB_CACHE) with ALL downloaded Dart/Flutter packages. Afterwards every project needs "flutter pub get", and global tools (dart pub global) are removed.'
    T 'arduino' 'dev' $true `
        'Arduino15 staging' 'Arduino15\staging - κατεβασμένα αρχεία εγκατάστασης πλακετών και βιβλιοθηκών.' `
        'Arduino15 staging' 'Arduino15\staging - downloaded board and library installers.'
    T 'androidmodels' 'dev' $true `
        'Android models (.android\models)' 'Ο φάκελος %USERPROFILE%\.android\models.' `
        'Android models (.android\models)' 'The %USERPROFILE%\.android\models folder.'
    T 'wsl' 'dev' $false `
        'Συμπίεση δίσκων WSL / Docker (αργό)' 'Κλείνει το WSL (wsl --shutdown) και συμπιέζει τους εικονικούς δίσκους ext4.vhdx / Docker με το diskpart, ώστε να επιστραφεί στα Windows ο χώρος που ελευθερώθηκε μέσα στο Linux. Δεν διαγράφει δεδομένα. Κλείστε πρώτα το Docker Desktop. Μπορεί να διαρκέσει αρκετά λεπτά.' `
        'Compact WSL / Docker disks (slow)' 'Shuts down WSL (wsl --shutdown) and compacts the ext4.vhdx / Docker virtual disks with diskpart, giving back to Windows the space freed inside Linux. No data is deleted. Quit Docker Desktop first. Can take several minutes.'

    T 'chrome' 'web' $false `
        'Google Chrome - cache' 'Cache, Code Cache, GPUCache, Service Worker cache και shader caches όλων των προφίλ. Κωδικοί, ιστορικό, σελιδοδείκτες και cookies ΔΕΝ αγγίζονται. Κλείστε το Chrome πριν.' `
        'Google Chrome - cache' 'Cache, Code Cache, GPUCache, Service Worker cache and shader caches of all profiles. Passwords, history, bookmarks and cookies are NOT touched. Close Chrome first.'
    T 'edge' 'web' $false `
        'Microsoft Edge - cache' 'Cache, Code Cache, GPUCache, Service Worker cache και shader caches όλων των προφίλ. Κωδικοί, ιστορικό, σελιδοδείκτες και cookies ΔΕΝ αγγίζονται. Κλείστε το Edge πριν.' `
        'Microsoft Edge - cache' 'Cache, Code Cache, GPUCache, Service Worker cache and shader caches of all profiles. Passwords, history, bookmarks and cookies are NOT touched. Close Edge first.'

    T 'discord' 'app' $true `
        'Discord - cache' 'Cache, Code Cache και GPUCache του Discord (και PTB / Canary). Οι συνομιλίες και ο λογαριασμός ΔΕΝ αγγίζονται. Κλείστε το Discord πριν (ή τικάρετε και τον τερματισμό εφαρμογών).' `
        'Discord - cache' 'Discord (and PTB / Canary) Cache, Code Cache and GPUCache. Chats and your account are NOT touched. Close Discord first (or also tick "Close apps").'
    T 'spotify' 'app' $true `
        'Spotify - cache' 'Ο φάκελος Spotify\Data (προσωρινή μνήμη τραγουδιών). Τα τραγούδια που έχετε κατεβάσει για offline ακρόαση ΔΕΝ αγγίζονται.' `
        'Spotify - cache' 'The Spotify\Data folder (streaming cache). Songs downloaded for offline listening are NOT touched.'
    T 'teams' 'app' $true `
        'Microsoft Teams - cache' 'Cache του κλασικού και του νέου Teams. Οι συνομιλίες είναι στο cloud και δεν χάνονται. Κλείστε το Teams πριν.' `
        'Microsoft Teams - cache' 'Cache of classic and new Teams. Chats live in the cloud and are not lost. Close Teams first.'
    T 'killapps' 'app' $false `
        'Τερματισμός εφαρμογών (Discord, Spotify, Steam...)' 'Τερματίζει (taskkill /F /T) τις εφαρμογές της λίστας στις Ρυθμίσεις. Εκτελείται ΠΡΩΤΟ ώστε να ξεκλειδώσουν τα αρχεία τους. Θα κλείσουν ΧΩΡΙΣ αποθήκευση!' `
        'Close apps (Discord, Spotify, Steam...)' 'Closes (taskkill /F /T) the apps listed in Settings. Runs FIRST so their files get unlocked. They close WITHOUT saving!'
)

# Εργασίες που υπήρχαν ήδη στη v6 (για σωστή μεταφορά των αποθηκευμένων επιλογών)
$V6Ids = 'cleanmgr', 'winupdate', 'usertemp', 'systemtemp', 'recycle', 'dns', 'dism', 'eventlogs', 'cursor', 'vscode',
         'antigravity', 'jetbrains', 'oldstudio', 'dart', 'flutter', 'gradle', 'npm', 'pip', 'arduino', 'androidmodels',
         'chrome', 'edge', 'killapps'

$DefaultKillList = 'discord.exe slack.exe Teams.exe ms-teams.exe Spotify.exe Steam.exe EpicGamesLauncher.exe WhatsApp.exe PowerToys.exe'
$DefaultProjects = Join-Path $env:USERPROFILE 'AndroidStudioProjects'

$MetaById  = @{}
$TaskNames = @{}
foreach ($t in $TaskMeta) { $MetaById[$t.Id] = $t }
function Update-TaskNames {
    foreach ($t in $TaskMeta) { $TaskNames[$t.Id] = $t.Name[$sync.Lang] }
}
Update-TaskNames
function Get-TaskDesc([string]$id) {
    if ($id -like 'custom:*') { return (L 'desc.custom') }
    return $MetaById[$id].Desc[$sync.Lang]
}

$SizeById = @{}
$DoneIds  = New-Object 'System.Collections.Generic.HashSet[string]'

$History = New-Object 'System.Collections.Generic.List[object]'
$h = Read-JsonFile $HistoryPath
if ($h) { foreach ($e in $h) { $History.Add($e) } }

# ============================================================
#  ΘΕΜΑΤΑ (φωτεινό / σκοτεινό)
# ============================================================
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SysOptNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern uint PrivateExtractIcons(string file, int index, int cx, int cy, IntPtr[] icons, uint[] ids, uint count, uint flags);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr icon);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
    [void][SysOptNative]::SetProcessDPIAware()
    # Δικό μας AppUserModelID: χωρίς αυτό η γραμμή εργασιών ομαδοποιεί το παράθυρο με το
    # powershell.exe και δείχνει το εικονίδιο του PowerShell αντί για το δικό μας.
    [void][SysOptNative]::SetCurrentProcessExplicitAppUserModelID('Kwstas147.UltimateSystemOptimizer')
} catch { }
[Windows.Forms.Application]::EnableVisualStyles()

function C([int]$r, [int]$g, [int]$b) { [Drawing.Color]::FromArgb($r, $g, $b) }
$Themes = @{
    Light = @{ Name = 'Light'; Bg = (C 243 243 243); Surface = [Drawing.Color]::White; Text = (C 28 28 28); Muted = (C 96 96 96)
               Border = (C 200 200 200); Grid = (C 232 232 232); Done = [Drawing.Color]::ForestGreen
               Bar = (C 0 95 184); BarHover = (C 0 66 130) }
    Dark  = @{ Name = 'Dark'; Bg = (C 32 32 32); Surface = (C 45 45 45); Text = (C 232 232 232); Muted = (C 160 160 160)
               Border = (C 75 75 75); Grid = (C 58 58 58); Done = (C 110 200 120)
               Bar = (C 77 160 255); BarHover = (C 150 200 255) }
}
$script:Theme = if ($Settings -and $Settings.Theme -eq 'Dark') { $Themes.Dark } else { $Themes.Light }
$Accent = C 0 95 184
$Danger = C 196 43 28

$gfx = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $S = $gfx.DpiX / 96.0; $gfx.Dispose()
# $script:S ρητά: οι handlers έχουν param($s, ...) και οι μεταβλητές του PowerShell δεν κάνουν
# διάκριση πεζών/κεφαλαίων, οπότε ένα σκέτο $S θα έπαιρνε τον sender αντί για την κλίμακα DPI.
function P([double]$n) { [int][math]::Round($n * $script:S) }

$UiFont    = New-Object Drawing.Font('Segoe UI', 9)
$BoldFont  = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)
$SmallFont = New-Object Drawing.Font('Segoe UI', 8)

# ============================================================
#  ΓΡΑΦΙΚΟ ΠΕΡΙΒΑΛΛΟΝ
# ============================================================
function New-Btn([int]$w, [string]$tag) {
    $b = New-Object Windows.Forms.Button
    $b.Height = P 32; $b.Tag = $tag; $b.FlatStyle = 'Flat'
    if ($w -gt 0) { $b.Width = P $w } else { $b.AutoSize = $true }
    $b
}
function New-Label {
    $l = New-Object Windows.Forms.Label
    $l.AutoSize = $true; $l.Margin = New-Object Windows.Forms.Padding(3, (P 9), 3, 3)
    $l
}
function New-Flow([string]$dock, [string]$dir) {
    $f = New-Object Windows.Forms.FlowLayoutPanel
    $f.Dock = $dock; $f.AutoSize = $true; $f.AutoSizeMode = 'GrowAndShrink'
    if ($dir) { $f.FlowDirection = $dir }
    $f
}
function New-ListView([int[]]$widths) {
    $lv = New-Object Windows.Forms.ListView
    $lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HideSelection = $false
    $lv.BorderStyle = 'FixedSingle'; $lv.OwnerDraw = $true
    foreach ($w in $widths) { [void]$lv.Columns.Add('', (P $w)) }
    # Ζωγραφίζουμε μόνοι μας τις κεφαλίδες ώστε να ακολουθούν το θέμα
    $lv.add_DrawColumnHeader({
        param($s, $e)
        $T = $script:Theme
        $br = New-Object Drawing.SolidBrush($T.Bg); $e.Graphics.FillRectangle($br, $e.Bounds); $br.Dispose()
        $pen = New-Object Drawing.Pen($T.Border)
        $e.Graphics.DrawLine($pen, $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1)
        $e.Graphics.DrawLine($pen, $e.Bounds.Right - 1, $e.Bounds.Top + 4, $e.Bounds.Right - 1, $e.Bounds.Bottom - 5)
        $pen.Dispose()
        $r = New-Object Drawing.Rectangle(($e.Bounds.X + (P 6)), $e.Bounds.Y, ($e.Bounds.Width - (P 8)), $e.Bounds.Height)
        [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $s.Font, $r, $T.Text,
            [Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis')
    })
    $lv.add_DrawItem({ param($s, $e) $e.DrawDefault = $true })
    $lv.add_DrawSubItem({ param($s, $e) $e.DrawDefault = $true })
    $lv
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Ultimate System Optimizer v7'
$form.AutoScaleMode = 'None'
$form.Font = $UiFont
$form.Size = New-Object Drawing.Size((P 1120), (P 780))
$form.MinimumSize = New-Object Drawing.Size((P 860), (P 600))
$form.StartPosition = 'CenterScreen'
# Εικονίδιο: από το .exe, αλλιώς SystemOptimizer.ico δίπλα στο script, αλλιώς του cleanmgr
foreach ($ic in @($IconPath, (Join-Path $BaseDir 'SystemOptimizer.ico'), "$env:SystemRoot\System32\cleanmgr.exe")) {
    if (-not $ic -or -not (Test-Path -LiteralPath $ic)) { continue }
    try {
        $form.Icon = if ($ic -like '*.ico') { New-Object Drawing.Icon($ic) } else { [Drawing.Icon]::ExtractAssociatedIcon($ic) }
        $script:IconFile = $ic
        break
    } catch { }
}

# --- Κεφαλίδα ---
$header = New-Object Windows.Forms.Panel
$header.Dock = 'Top'; $header.Height = P 62; $header.BackColor = $Accent; $header.ForeColor = [Drawing.Color]::White
$lblTitle = New-Object Windows.Forms.Label
$lblTitle.Text = 'Ultimate System Optimizer'; $lblTitle.AutoSize = $true
$lblTitle.Font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object Drawing.Point((P 14), (P 6))
$lblFree = New-Object Windows.Forms.Label
$lblFree.AutoSize = $true; $lblFree.Location = New-Object Drawing.Point((P 16), (P 38))
$headerBtns = New-Object Windows.Forms.Panel
$headerBtns.Dock = 'Right'; $headerBtns.Width = P 410
function New-HeaderBtn([int]$x, [int]$w) {
    $b = New-Object Windows.Forms.Button
    $b.FlatStyle = 'Flat'; $b.Size = New-Object Drawing.Size((P $w), (P 32)); $b.Location = New-Object Drawing.Point((P $x), (P 15))
    $b.ForeColor = [Drawing.Color]::White; $b.BackColor = $Accent; $b.FlatAppearance.BorderColor = [Drawing.Color]::White
    $b
}
$btnAbout = New-HeaderBtn 6 110
$btnLang  = New-HeaderBtn 124 100
$btnTheme = New-HeaderBtn 232 170
$headerBtns.Controls.AddRange(@($btnAbout, $btnLang, $btnTheme))
$header.Controls.AddRange(@($headerBtns, $lblTitle, $lblFree))

# --- Πλοήγηση (σελίδες) ---
$navBar = New-Object Windows.Forms.Panel
$navBar.Dock = 'Top'; $navBar.Height = P 46; $navBar.Padding = New-Object Windows.Forms.Padding((P 8), (P 7), (P 8), 0)
$navFlow = New-Object Windows.Forms.FlowLayoutPanel
$navFlow.Dock = 'Fill'; $navFlow.WrapContents = $false
$btnNavClean = New-Btn 170 'nav'
$btnNavBig   = New-Btn 240 'nav'
$btnNavHist  = New-Btn 140 'nav'
$navFlow.Controls.AddRange(@($btnNavClean, $btnNavBig, $btnNavHist))
$navBar.Controls.Add($navFlow)

# --- Κάτω μπάρα (κοινή): πρόοδος, κατάσταση, διακοπή ---
$bottom = New-Object Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = P 84; $bottom.Padding = New-Object Windows.Forms.Padding((P 10), (P 6), (P 10), (P 8))
$pb = New-Object Windows.Forms.ProgressBar
$pb.Dock = 'Top'; $pb.Height = P 16; $pb.MarqueeAnimationSpeed = 30
$lblStatus = New-Object Windows.Forms.Label
$lblStatus.Dock = 'Top'; $lblStatus.Height = P 24; $lblStatus.TextAlign = 'MiddleLeft'; $lblStatus.AutoEllipsis = $true
$flowBtns = New-Object Windows.Forms.FlowLayoutPanel
$flowBtns.Dock = 'Fill'; $flowBtns.FlowDirection = 'RightToLeft'; $flowBtns.WrapContents = $false
$btnStop = New-Btn 110 ''; $btnStop.Enabled = $false
$btnLog  = New-Btn 160 ''
$flowBtns.Controls.AddRange(@($btnStop, $btnLog))
$bottom.Controls.Add($flowBtns); $bottom.Controls.Add($lblStatus); $bottom.Controls.Add($pb)

$content = New-Object Windows.Forms.Panel
$content.Dock = 'Fill'

# ------------------------------------------------------------
#  ΣΕΛΙΔΑ 1: Καθαρισμός
# ------------------------------------------------------------
$pageClean = New-Object Windows.Forms.Panel
$pageClean.Dock = 'Fill'

$split = New-Object Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Panel1.Padding = New-Object Windows.Forms.Padding((P 8))
$split.Panel2.Padding = New-Object Windows.Forms.Padding((P 8))

$tree = New-Object Windows.Forms.TreeView
$tree.Dock = 'Fill'; $tree.CheckBoxes = $true; $tree.HideSelection = $false
$tree.ItemHeight = P 24; $tree.ShowNodeToolTips = $true; $tree.BorderStyle = 'FixedSingle'
$tree.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$lblTotal = New-Object Windows.Forms.Label
$lblTotal.Dock = 'Bottom'; $lblTotal.Height = P 26; $lblTotal.TextAlign = 'MiddleLeft'
$flowLeft = New-Flow 'Bottom' ''
$btnAll     = New-Btn 0 ''
$btnNone    = New-Btn 0 ''
$btnDefault = New-Btn 0 ''
$btnAddDir  = New-Btn 0 ''
$btnDelDir  = New-Btn 0 ''
$flowLeft.Controls.AddRange(@($btnAll, $btnNone, $btnDefault, $btnAddDir, $btnDelDir))
$split.Panel1.Controls.Add($tree); $split.Panel1.Controls.Add($lblTotal); $split.Panel1.Controls.Add($flowLeft)

$grpDesc = New-Object Windows.Forms.GroupBox
$grpDesc.Dock = 'Top'; $grpDesc.Height = P 180
$tbDesc = New-Object Windows.Forms.TextBox
$tbDesc.Dock = 'Fill'; $tbDesc.Multiline = $true; $tbDesc.ReadOnly = $true; $tbDesc.ScrollBars = 'Vertical'
$tbDesc.BorderStyle = 'None'
$grpDesc.Controls.Add($tbDesc)

$grpOpt = New-Object Windows.Forms.GroupBox
$grpOpt.Dock = 'Top'; $grpOpt.Height = P 100
$tl = New-Object Windows.Forms.TableLayoutPanel
$tl.Dock = 'Fill'; $tl.ColumnCount = 3; $tl.RowCount = 2
[void]$tl.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
[void]$tl.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
[void]$tl.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
[void]$tl.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
[void]$tl.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
$lblProj = New-Object Windows.Forms.Label
$lblProj.AutoSize = $true; $lblProj.Anchor = 'Left'
$tbProj = New-Object Windows.Forms.TextBox; $tbProj.Dock = 'Fill'
$btnProj = New-Btn 36 ''; $btnProj.Height = P 26; $btnProj.Text = '...'
$lblKill = New-Object Windows.Forms.Label
$lblKill.AutoSize = $true; $lblKill.Anchor = 'Left'
$tbKill = New-Object Windows.Forms.TextBox; $tbKill.Dock = 'Fill'
$tl.Controls.Add($lblProj, 0, 0); $tl.Controls.Add($tbProj, 1, 0); $tl.Controls.Add($btnProj, 2, 0)
$tl.Controls.Add($lblKill, 0, 1); $tl.Controls.Add($tbKill, 1, 1); $tl.SetColumnSpan($tbKill, 2)
$grpOpt.Controls.Add($tl)

$grpLog = New-Object Windows.Forms.GroupBox
$grpLog.Dock = 'Fill'
$tbLog = New-Object Windows.Forms.TextBox
$tbLog.Dock = 'Fill'; $tbLog.Multiline = $true; $tbLog.ReadOnly = $true; $tbLog.ScrollBars = 'Vertical'
$tbLog.Font = New-Object Drawing.Font('Consolas', 9)
$tbLog.BackColor = C 30 30 30; $tbLog.ForeColor = C 220 220 220
$grpLog.Controls.Add($tbLog)

$split.Panel2.Controls.Add($grpLog); $split.Panel2.Controls.Add($grpOpt); $split.Panel2.Controls.Add($grpDesc)

$cleanBar = New-Flow 'Bottom' 'RightToLeft'
$cleanBar.Padding = New-Object Windows.Forms.Padding((P 6), 0, (P 6), 0)
$btnClean = New-Btn 180 'accent'
$btnClean.Font = $BoldFont
$btnScan = New-Btn 160 ''
$cleanBar.Controls.AddRange(@($btnClean, $btnScan))
$pageClean.Controls.Add($split); $pageClean.Controls.Add($cleanBar)

# ------------------------------------------------------------
#  ΣΕΛΙΔΑ 2: Μεγάλα αρχεία & node_modules
# ------------------------------------------------------------
$pageBig = New-Object Windows.Forms.Panel
$pageBig.Dock = 'Fill'; $pageBig.Padding = New-Object Windows.Forms.Padding((P 8))

$bigTop = New-Flow 'Top' ''
$lblSearchIn = New-Label
$tbRoot = New-Object Windows.Forms.TextBox; $tbRoot.Width = P 280; $tbRoot.Margin = New-Object Windows.Forms.Padding(3, (P 6), 3, 3)
$btnRoot = New-Btn 36 ''; $btnRoot.Text = '...'
$lblMinSize = New-Label
$numMin = New-Object Windows.Forms.NumericUpDown
$numMin.Minimum = 1; $numMin.Maximum = 100000; $numMin.Increment = 50; $numMin.Width = P 80
$numMin.Margin = New-Object Windows.Forms.Padding(3, (P 6), (P 12), 3)
$btnFindBig = New-Btn 0 'accent'
$btnFindDev = New-Btn 0 'accent'
$bigTop.Controls.AddRange(@($lblSearchIn, $tbRoot, $btnRoot, $lblMinSize, $numMin, $btnFindBig, $btnFindDev))

$lblBigHint = New-Object Windows.Forms.Label
$lblBigHint.Dock = 'Top'; $lblBigHint.Height = P 26; $lblBigHint.TextAlign = 'MiddleLeft'

$lvBig = New-ListView @(560, 100, 140, 120)
$lvBig.CheckBoxes = $true

$bigBottom = New-Flow 'Bottom' 'RightToLeft'
$btnDelSel  = New-Btn 0 'danger'
$btnOpenLoc = New-Btn 0 ''
$btnBigNone = New-Btn 0 ''
$btnBigAll  = New-Btn 0 ''
$chkRecycle = New-Object Windows.Forms.CheckBox
$chkRecycle.AutoSize = $true
$chkRecycle.Margin = New-Object Windows.Forms.Padding((P 12), (P 9), (P 12), 3)
$lblBigTotal = New-Label
$bigBottom.Controls.AddRange(@($btnDelSel, $btnOpenLoc, $btnBigNone, $btnBigAll, $chkRecycle, $lblBigTotal))

$pageBig.Controls.Add($lvBig); $pageBig.Controls.Add($bigBottom); $pageBig.Controls.Add($lblBigHint); $pageBig.Controls.Add($bigTop)

# ------------------------------------------------------------
#  ΣΕΛΙΔΑ 3: Ιστορικό
# ------------------------------------------------------------
$pageHist = New-Object Windows.Forms.Panel
$pageHist.Dock = 'Fill'; $pageHist.Padding = New-Object Windows.Forms.Padding((P 8))

$lblHistSum = New-Object Windows.Forms.Label
$lblHistSum.Dock = 'Top'; $lblHistSum.Height = P 30; $lblHistSum.TextAlign = 'MiddleLeft'; $lblHistSum.Font = $BoldFont

$chart = New-Object Windows.Forms.Panel
$chart.Dock = 'Top'; $chart.Height = P 260
$chart.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($chart, $true, $null)
$chartTip = New-Object Windows.Forms.ToolTip

$histGap = New-Object Windows.Forms.Panel
$histGap.Dock = 'Top'; $histGap.Height = P 8

$lvHist = New-ListView @(160, 130, 170, 100, 90, 140)

$histBottom = New-Flow 'Bottom' 'RightToLeft'
$btnHistClear = New-Btn 0 ''
$histBottom.Controls.Add($btnHistClear)

$pageHist.Controls.Add($lvHist); $pageHist.Controls.Add($histBottom); $pageHist.Controls.Add($histGap)
$pageHist.Controls.Add($chart); $pageHist.Controls.Add($lblHistSum)

$content.Controls.AddRange(@($pageClean, $pageBig, $pageHist))
$form.Controls.Add($content); $form.Controls.Add($navBar); $form.Controls.Add($bottom); $form.Controls.Add($header)

$tip = New-Object Windows.Forms.ToolTip

# ============================================================
#  ΒΟΗΘΗΤΙΚΕΣ ΣΥΝΑΡΤΗΣΕΙΣ UI
# ============================================================
$script:busy = $false
$script:suppress = $false
$script:fillingBig = $false
$script:ps = $null
$script:handle = $null
$script:lastDone = $null
$script:page = 0
$script:hoverIdx = -1
$script:chartGeom = $null
$script:bigSortCol = 1
$script:bigSortDesc = $true
$GroupNodes = @{}
$NodeById = @{}
$BigItemByPath = @{}

function Add-LogLine([string]$s) { $tbLog.AppendText(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $s) + "`r`n") }

function Get-LeafNodes { foreach ($g in $tree.Nodes) { foreach ($n in $g.Nodes) { $n } } }

function Update-NodeText($n) {
    $id = [string]$n.Tag
    $t = $TaskNames[$id]
    if ($SizeById.ContainsKey($id) -and $SizeById[$id] -ge 0) { $t += '   -  ' + (Format-Size $SizeById[$id]) }
    if ($DoneIds.Contains($id)) { $t = '✓ ' + $t; $n.ForeColor = $script:Theme.Done } else { $n.ForeColor = [Drawing.Color]::Empty }
    $n.Text = $t
    $n.ToolTipText = Get-TaskDesc $id
}

function Update-GroupState($g) {
    if ($g.Nodes.Count -eq 0) { return }
    $all = $true
    foreach ($c in $g.Nodes) { if (-not $c.Checked) { $all = $false } }
    $script:suppress = $true
    $g.Checked = $all
    $script:suppress = $false
}

function Update-SelectedTotal {
    $count = 0; $sum = [int64]0; $known = $false
    foreach ($n in (Get-LeafNodes)) {
        if (-not $n.Checked) { continue }
        $count++
        $id = [string]$n.Tag
        if ($SizeById.ContainsKey($id) -and $SizeById[$id] -ge 0) { $sum += $SizeById[$id]; $known = $true }
    }
    if ($known) { $lblTotal.Text = L 'total.known' $count (Format-Size $sum) }
    else { $lblTotal.Text = L 'total.unknown' $count }
}

function Update-Free { $lblFree.Text = L 'free.header' $env:SystemDrive (Format-Size (Get-FreeBytes)) $LogPath }

function Add-TaskNode([string]$id, [string]$groupKey, [bool]$checked) {
    $n = New-Object Windows.Forms.TreeNode
    $n.Tag = $id
    $n.Checked = $checked
    Update-NodeText $n
    [void]$GroupNodes[$groupKey].Nodes.Add($n)
    $NodeById[$id] = $n
    $n
}

function Set-Busy([bool]$b) {
    $script:busy = $b
    foreach ($c in @($btnClean, $btnScan, $btnFindBig, $btnFindDev, $btnDelSel, $btnHistClear, $flowLeft, $grpOpt, $tbRoot, $btnRoot, $numMin, $btnLang)) {
        $c.Enabled = -not $b
    }
    $btnStop.Enabled = $b
    $form.UseWaitCursor = $b
}

function Save-Settings {
    try {
        $data = [ordered]@{
            Lang         = $sync.Lang
            Theme        = $script:Theme.Name
            Known        = @($TaskMeta | ForEach-Object { $_.Id })
            Checked      = @(Get-LeafNodes | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Tag })
            Custom       = @($GroupNodes['custom'].Nodes | ForEach-Object { ([string]$_.Tag).Substring(7) })
            ProjectsRoot = $tbProj.Text
            KillList     = $tbKill.Text
            ScanRoot     = $tbRoot.Text
            MinMB        = [int]$numMin.Value
            Recycle      = $chkRecycle.Checked
        }
        $data | ConvertTo-Json | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    } catch { }
}

function Show-Desc($node) {
    if (-not $node) { $tbDesc.Text = L 'desc.initial'; return }
    $id = [string]$node.Tag
    if ($id -like 'group:*') {
        $tbDesc.Text = L 'desc.group' $node.Text.Trim()
        return
    }
    $sync.ProjectsRoot = $tbProj.Text
    $paths = @(Get-TaskPaths $id)
    $text = Get-TaskDesc $id
    if ($id -eq 'wsl') {
        $v = @(Get-WslVhdx)
        $text += "`r`n`r`n" + (L 'desc.wsl' $v.Count)
        foreach ($f in $v) { $text += "`r`n  • $f  ($(Format-Size (Get-Item -LiteralPath $f -Force).Length))" }
    }
    if ($paths.Count -gt 0) {
        $exist = @($paths | Where-Object { Test-Path -LiteralPath $_ })
        $text += "`r`n`r`n" + (L 'desc.found' $exist.Count $paths.Count)
        foreach ($p in ($exist | Select-Object -First 40)) { $text += "`r`n  • $p" }
        if ($exist.Count -gt 40) { $text += "`r`n" + (L 'desc.more' ($exist.Count - 40)) }
        if ($exist.Count -eq 0) { $text += "`r`n" + (L 'desc.none') }
    }
    $tbDesc.Text = $text
}

function Start-Worker([string]$mode, [string[]]$ids) {
    $sync.Mode = $mode
    $sync.Items = $ids
    $sync.Cancel = $false
    $sync.ProjectsRoot = $tbProj.Text
    $sync.KillList = $tbKill.Text
    $sync.ScanRoot = $tbRoot.Text
    $sync.MinBytes = [int64]$numMin.Value * 1MB
    $sync.UseRecycle = $chkRecycle.Checked
    $sync.Names = $TaskNames.Clone()
    $script:lastDone = $null
    if (@('bigfiles', 'devdirs', 'delete') -contains $mode) { $pb.Style = 'Marquee' } else { $pb.Style = 'Continuous'; $pb.Value = 0 }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $script:ps = [powershell]::Create()
    $script:ps.Runspace = $rs
    [void]$script:ps.AddScript($LangCore + "`r`n" + $WorkerCore + "`r`nStart-Main")
    Set-Busy $true
    $script:handle = $script:ps.BeginInvoke()
    $timer.Start()
}

function Complete-Worker {
    try { [void]$script:ps.EndInvoke($script:handle) } catch { Add-LogLine (L 'w.fatal' $_.Exception.Message) }
    try { $script:ps.Runspace.Dispose(); $script:ps.Dispose() } catch { }
    $script:handle = $null
    $timer.Stop()
    $pb.Style = 'Continuous'
    Set-Busy $false
    Update-Free
    Update-SelectedTotal
    $d = $script:lastDone
    if (-not $d -or $d.Error) { return }
    switch ($d.Mode) {
        'clean' {
            Add-HistoryEntry $d
            Invoke-DoneSound
            $msg = L 'done.summary' (Format-Size $d.Freed) (Format-Size $d.Free) ('{0:hh\:mm\:ss}' -f $d.Elapsed)
            $head = if ($d.Cancelled) { L 'done.cleanCancel' } else { L 'done.cleanOk' }
            [void][Windows.Forms.MessageBox]::Show($form, "$head`n`n$msg", 'System Optimizer', 'OK', 'Information')
        }
        'delete' {
            $lblStatus.Text = L 'done.delete' (Format-Size $d.Freed)
            Update-BigTotal
        }
        { $_ -eq 'bigfiles' -or $_ -eq 'devdirs' } {
            $lblStatus.Text = L 'done.found' $lvBig.Items.Count
        }
    }
}

# --- Ήχος ολοκλήρωσης (tada των Windows, αλλιώς ο ήχος συστήματος) ---
function Invoke-DoneSound {
    try {
        $wav = "$env:SystemRoot\Media\tada.wav"
        if (Test-Path -LiteralPath $wav) { (New-Object Media.SoundPlayer $wav).Play() }
        else { [Media.SystemSounds]::Asterisk.Play() }
    } catch { }
}

# --- Μεγάλα αρχεία: λίστα, ταξινόμηση, σύνολα ---
function Add-BigResults($items) {
    $script:fillingBig = $true
    $lvBig.BeginUpdate()
    $lvBig.Items.Clear(); $BigItemByPath.Clear()
    foreach ($o in @($items)) {
        $li = New-Object Windows.Forms.ListViewItem([string]$o.Path)
        [void]$li.SubItems.Add((Format-Size $o.Bytes))
        [void]$li.SubItems.Add(([datetime]$o.Modified).ToString('yyyy-MM-dd HH:mm'))
        [void]$li.SubItems.Add([string]$o.Kind)
        $li.Tag = $o
        [void]$lvBig.Items.Add($li)
        $BigItemByPath[[string]$o.Path] = $li
    }
    $lvBig.EndUpdate()
    $script:fillingBig = $false
    Update-BigTotal
}

function Update-BigTotal {
    $c = 0; $sum = [int64]0
    foreach ($li in $lvBig.CheckedItems) { $c++; $sum += [int64]$li.Tag.Bytes }
    $lblBigTotal.Text = L 'big.selected' $c (Format-Size $sum)
}

function Sort-BigList {
    $items = @($lvBig.Items | ForEach-Object { $_ })
    if ($items.Count -eq 0) { return }
    $key = switch ($script:bigSortCol) {
        0 { { [string]$_.Tag.Path } }
        1 { { [int64]$_.Tag.Bytes } }
        2 { { [datetime]$_.Tag.Modified } }
        default { { [string]$_.Tag.Kind } }
    }
    $sorted = @($items | Sort-Object -Property $key -Descending:$script:bigSortDesc)
    $script:fillingBig = $true
    $lvBig.BeginUpdate(); $lvBig.Items.Clear(); $lvBig.Items.AddRange([Windows.Forms.ListViewItem[]]$sorted); $lvBig.EndUpdate()
    $script:fillingBig = $false
}

# --- Ιστορικό ---
function Save-History {
    try { ConvertTo-Json -InputObject @($History.ToArray()) | Set-Content -LiteralPath $HistoryPath -Encoding UTF8 } catch { }
}

function Add-HistoryEntry($d) {
    $History.Add([pscustomobject]@{
        Date      = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        Freed     = [int64]$d.Freed
        Free      = [int64]$d.Free
        Seconds   = [int]$d.Elapsed.TotalSeconds
        Tasks     = [int]$d.Tasks
        Cancelled = [bool]$d.Cancelled
    })
    Save-History
    Update-History
}

function Update-History {
    $lvHist.BeginUpdate(); $lvHist.Items.Clear()
    for ($i = $History.Count - 1; $i -ge 0; $i--) {
        $r = $History[$i]
        $li = New-Object Windows.Forms.ListViewItem([string]$r.Date)
        [void]$li.SubItems.Add((Format-Size $r.Freed))
        [void]$li.SubItems.Add((Format-Size $r.Free))
        [void]$li.SubItems.Add(('{0:hh\:mm\:ss}' -f [TimeSpan]::FromSeconds([int]$r.Seconds)))
        [void]$li.SubItems.Add([string]$r.Tasks)
        [void]$li.SubItems.Add($(if ($r.Cancelled) { L 'hist.cancelled' } else { '' }))
        [void]$lvHist.Items.Add($li)
    }
    $lvHist.EndUpdate()
    if ($History.Count -gt 0) {
        $sum = [int64]0; foreach ($r in $History) { $sum += [int64]$r.Freed }
        $lblHistSum.Text = L 'hist.sum' (Format-Size $sum) $History.Count (Format-Size ($sum / $History.Count))
    } else {
        $lblHistSum.Text = L 'hist.empty'
    }
    $chart.Invalidate()
}

function Get-NiceMax([double]$v) {
    if ($v -le 0) { return 1.0 }
    $exp = [math]::Pow(10, [math]::Floor([math]::Log10($v)))
    foreach ($m in 1, 2, 4, 5, 10) { if ($m * $exp -ge $v) { return $m * $exp } }
    return 10 * $exp
}

function New-TopRoundedPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    if ($r -lt 1) { $p.AddRectangle((New-Object Drawing.RectangleF($x, $y, $w, $h))); return $p }
    [single]$d = $r * 2
    $p.AddArc($x, $y, $d, $d, [single]180, [single]90)
    $p.AddArc([single]($x + $w - $d), $y, $d, $d, [single]270, [single]90)
    $p.AddLine([single]($x + $w), [single]($y + $r), [single]($x + $w), [single]($y + $h))
    $p.AddLine([single]($x + $w), [single]($y + $h), $x, [single]($y + $h))
    $p.CloseFigure()
    return $p
}

# --- Θέμα ---
function Apply-ThemeTo($parent) {
    $T = $script:Theme
    foreach ($ch in $parent.Controls) {
        if ($ch -eq $header -or $ch -eq $tbLog -or $ch -eq $chart) { continue }
        if ($ch -is [Windows.Forms.Button]) {
            $ch.FlatStyle = 'Flat'
            switch ([string]$ch.Tag) {
                'accent' { $ch.BackColor = $Accent; $ch.ForeColor = [Drawing.Color]::White; $ch.FlatAppearance.BorderColor = $Accent }
                'danger' { $ch.BackColor = $Danger; $ch.ForeColor = [Drawing.Color]::White; $ch.FlatAppearance.BorderColor = $Danger }
                'nav'    { }
                default  { $ch.BackColor = $T.Surface; $ch.ForeColor = $T.Text; $ch.FlatAppearance.BorderColor = $T.Border }
            }
            continue
        }
        if ($ch -is [Windows.Forms.TextBox] -or $ch -is [Windows.Forms.TreeView] -or $ch -is [Windows.Forms.ListView] -or $ch -is [Windows.Forms.NumericUpDown]) {
            $ch.BackColor = $T.Surface; $ch.ForeColor = $T.Text
            continue
        }
        $ch.BackColor = $T.Bg; $ch.ForeColor = $T.Text
        Apply-ThemeTo $ch
    }
}

function Update-Nav {
    $T = $script:Theme
    $navs = @($btnNavClean, $btnNavBig, $btnNavHist)
    for ($i = 0; $i -lt 3; $i++) {
        $b = $navs[$i]
        if ($i -eq $script:page) {
            $b.BackColor = $Accent; $b.ForeColor = [Drawing.Color]::White; $b.FlatAppearance.BorderColor = $Accent; $b.Font = $BoldFont
        } else {
            $b.BackColor = $T.Surface; $b.ForeColor = $T.Text; $b.FlatAppearance.BorderColor = $T.Border; $b.Font = $UiFont
        }
    }
}

function Set-Theme($theme) {
    $script:Theme = $theme
    $T = $theme
    $form.BackColor = $T.Bg; $form.ForeColor = $T.Text
    Apply-ThemeTo $form
    $tbDesc.BackColor = $T.Bg
    $chart.BackColor = $T.Surface
    $btnTheme.Text = if ($T.Name -eq 'Dark') { L 'theme.toLight' } else { L 'theme.toDark' }
    Update-Nav
    foreach ($n in (Get-LeafNodes)) { Update-NodeText $n }
    $lvBig.Invalidate(); $lvHist.Invalidate(); $chart.Invalidate()
    if ($form.IsHandleCreated) {
        $v = [int]($T.Name -eq 'Dark')
        try { [void][SysOptNative]::DwmSetWindowAttribute($form.Handle, 20, [ref]$v, 4) } catch { }
    }
}

# --- Γλώσσα: όλα τα κείμενα του παραθύρου ---
function Set-Language([string]$lang) {
    $sync.Lang = $lang
    Update-TaskNames
    $btnLang.Text = L 'lang.button'; $btnAbout.Text = L 'btn.about'
    $btnTheme.Text = if ($script:Theme.Name -eq 'Dark') { L 'theme.toLight' } else { L 'theme.toDark' }
    $btnNavClean.Text = L 'nav.clean'; $btnNavBig.Text = L 'nav.big'; $btnNavHist.Text = L 'nav.hist'
    $btnStop.Text = L 'btn.stop'; $btnLog.Text = L 'btn.log'
    $btnAll.Text = L 'btn.all'; $btnNone.Text = L 'btn.none'; $btnDefault.Text = L 'btn.defaults'
    $btnAddDir.Text = L 'btn.addDir'; $btnDelDir.Text = L 'btn.delDir'
    $btnClean.Text = L 'btn.clean'; $btnScan.Text = L 'btn.scan'
    $btnFindBig.Text = L 'btn.findBig'; $btnFindDev.Text = L 'btn.findDev'
    $btnDelSel.Text = L 'btn.delSel'; $btnOpenLoc.Text = L 'btn.openLoc'
    $btnBigAll.Text = L 'btn.all'; $btnBigNone.Text = L 'btn.none'; $btnHistClear.Text = L 'btn.histClear'
    $grpDesc.Text = L 'box.desc'; $grpOpt.Text = L 'box.opt'; $grpLog.Text = L 'box.log'
    $lblProj.Text = L 'opt.projects'; $lblKill.Text = L 'opt.kill'
    $lblSearchIn.Text = L 'lbl.searchIn'; $lblMinSize.Text = L 'lbl.minSize'
    $lblBigHint.Text = L 'big.hint'; $chkRecycle.Text = L 'chk.recycle'
    $cols = 'col.path', 'col.size', 'col.modified', 'col.type'
    for ($i = 0; $i -lt $cols.Count; $i++) { $lvBig.Columns[$i].Text = L $cols[$i] }
    $cols = 'col.date', 'col.freed', 'col.freeAfter', 'col.duration', 'col.tasks', 'col.note'
    for ($i = 0; $i -lt $cols.Count; $i++) { $lvHist.Columns[$i].Text = L $cols[$i] }
    $tip.SetToolTip($tbKill, (L 'tip.kill'))
    $tip.SetToolTip($btnScan, (L 'tip.scan'))
    $tip.SetToolTip($btnFindDev, (L 'tip.findDev'))
    $tip.SetToolTip($chkRecycle, (L 'tip.recycle'))
    $tip.SetToolTip($btnLang, (L 'tip.lang'))
    $tip.SetToolTip($btnAbout, (L 'tip.about'))
    foreach ($k in $GroupKeys) { $GroupNodes[$k].Text = (L "grp.$k") + '      ' }   # κενά: αποφυγή "κομμένου" bold κειμένου
    foreach ($n in (Get-LeafNodes)) { Update-NodeText $n }
    Show-Desc $tree.SelectedNode
    if (-not $script:busy) { $lblStatus.Text = L 'status.ready' }
    Update-Free; Update-SelectedTotal; Update-BigTotal; Update-History
    $lvBig.Invalidate(); $lvHist.Invalidate()
}

function Show-Page([int]$i) {
    $script:page = $i
    $pageClean.Visible = ($i -eq 0); $pageBig.Visible = ($i -eq 1); $pageHist.Visible = ($i -eq 2)
    Update-Nav
}

# ============================================================
#  ΣΧΕΤΙΚΑ / ABOUT: έκδοση, άδεια χρήσης, αναφορές
#  Το κείμενο της άδειας είναι ενσωματωμένο, ώστε να συνοδεύει
#  και το αυτόνομο .exe (απαίτηση της MIT και της CC BY 4.0).
# ============================================================
$AppVersion = '7.0'
$RepoUrl    = 'https://github.com/kwstas147/SystemOptimizer'
$IconUrl    = 'https://icon-icons.com/icon/cleaner-brom/53211'
$CcByUrl    = 'https://creativecommons.org/licenses/by/4.0/'
$LicenseText = @'
MIT License

Copyright (c) 2026 Kwstas (kwstas147)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---------------------------------------------------------------------------

Application icon: "Cleaner brom" by Funline Icons
https://icon-icons.com/icon/cleaner-brom/53211
Licensed under CC BY 4.0: https://creativecommons.org/licenses/by/4.0/
The application icon is adapted (redrawn) from the original.
The icon is NOT covered by the MIT License above.
'@

# Παράθυρο διαλόγου με το τρέχον θέμα (και σκοτεινή γραμμή τίτλου)
function New-DialogForm([string]$title) {
    $d = New-Object Windows.Forms.Form
    $d.Text = $title; $d.Font = $UiFont; $d.AutoScaleMode = 'None'
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.ShowInTaskbar = $false; $d.StartPosition = 'CenterParent'; $d.Icon = $form.Icon
    $d.BackColor = $script:Theme.Bg; $d.ForeColor = $script:Theme.Text
    $d.add_HandleCreated({
        param($s, $e)
        $v = [int]($script:Theme.Name -eq 'Dark')
        try { [void][SysOptNative]::DwmSetWindowAttribute($s.Handle, 20, [ref]$v, 4) } catch { }
    })
    $d
}

# Εικονίδιο σε μεγάλο μέγεθος. Τα frames του .ico είναι συμπιεσμένα PNG, που το Drawing.Icon
# του .NET 4 δεν μετατρέπει σωστά, οπότε το διαβάζουν τα Windows (από .ico ή από .exe).
function Get-AppIconImage([int]$size) {
    $px = P $size
    if ($script:IconFile) {
        $h = New-Object IntPtr[] 1; $ids = New-Object uint32[] 1
        try {
            if ([SysOptNative]::PrivateExtractIcons($script:IconFile, 0, $px, $px, $h, $ids, 1, 0) -eq 1 -and $h[0] -ne [IntPtr]::Zero) {
                $bmp = [Drawing.Icon]::FromHandle($h[0]).ToBitmap()
                [void][SysOptNative]::DestroyIcon($h[0])
                return $bmp
            }
        } catch { }
    }
    if ($form.Icon) { return $form.Icon.ToBitmap() }
    return $null
}

function New-AboutText([string]$text, [int]$width, [bool]$bold) {
    $l = New-Object Windows.Forms.Label
    $l.AutoSize = $true; $l.MaximumSize = New-Object Drawing.Size($width, 0); $l.Text = $text
    if ($bold) { $l.Font = $BoldFont; $l.Margin = New-Object Windows.Forms.Padding(0, (P 12), 0, (P 2)) }
    else { $l.Margin = New-Object Windows.Forms.Padding(0, (P 2), 0, (P 2)) }
    $l
}

function New-AboutLink([string]$text, [string]$url) {
    $l = New-Object Windows.Forms.LinkLabel
    $l.AutoSize = $true; $l.Text = $text; $l.Tag = $url
    $l.Margin = New-Object Windows.Forms.Padding(0, (P 4), (P 18), 0)
    $l.add_LinkClicked({
        param($s, $e)
        try { Start-Process ([string]$s.Tag) } catch { }
    })
    $l
}

function Show-License($owner) {
    $d = New-DialogForm (L 'about.licenseTitle')
    $d.ClientSize = New-Object Drawing.Size((P 640), (P 470))
    $d.Padding = New-Object Windows.Forms.Padding((P 12))
    $tb = New-Object Windows.Forms.TextBox
    $tb.Dock = 'Fill'; $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'
    $tb.BorderStyle = 'FixedSingle'; $tb.Font = New-Object Drawing.Font('Consolas', 9)
    $tb.Text = $LicenseText -replace "`r?`n", "`r`n"
    $bar = New-Flow 'Bottom' 'RightToLeft'
    $bar.Padding = New-Object Windows.Forms.Padding(0, (P 8), 0, 0)
    $ok = New-Btn 120 'accent'; $ok.Text = L 'about.close'; $ok.DialogResult = 'OK'
    $bar.Controls.Add($ok)
    $d.Controls.Add($tb); $d.Controls.Add($bar)
    Apply-ThemeTo $d
    $d.AcceptButton = $ok; $d.CancelButton = $ok; $d.ActiveControl = $ok
    [void]$d.ShowDialog($owner)
    $d.Dispose()
}

function Show-About {
    $T = $script:Theme
    $w = P 520
    $d = New-DialogForm (L 'about.title')
    $d.AutoSize = $true; $d.AutoSizeMode = 'GrowAndShrink'

    $body = New-Object Windows.Forms.FlowLayoutPanel
    $body.FlowDirection = 'TopDown'; $body.WrapContents = $false
    $body.AutoSize = $true; $body.AutoSizeMode = 'GrowAndShrink'
    $body.Padding = New-Object Windows.Forms.Padding((P 20), (P 16), (P 20), (P 14))

    # Εικονίδιο, όνομα, έκδοση
    $top = New-Object Windows.Forms.FlowLayoutPanel
    $top.AutoSize = $true; $top.WrapContents = $false; $top.Margin = New-Object Windows.Forms.Padding(0, 0, 0, (P 6))
    $pic = New-Object Windows.Forms.PictureBox
    $pic.Size = New-Object Drawing.Size((P 64), (P 64)); $pic.SizeMode = 'Zoom'
    $pic.Image = Get-AppIconImage 64
    $names = New-Object Windows.Forms.FlowLayoutPanel
    $names.FlowDirection = 'TopDown'; $names.AutoSize = $true; $names.WrapContents = $false
    $names.Margin = New-Object Windows.Forms.Padding((P 12), (P 4), 0, 0)
    $lblName = New-Object Windows.Forms.Label
    $lblName.AutoSize = $true; $lblName.Text = 'Ultimate System Optimizer'
    $lblName.Font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold)
    $lblVer = New-Object Windows.Forms.Label
    $lblVer.AutoSize = $true; $lblVer.Text = L 'about.version' $AppVersion
    $names.Controls.AddRange(@($lblName, $lblVer))
    $top.Controls.AddRange(@($pic, $names))

    $lnkRepo = New-AboutLink (L 'about.repo') $RepoUrl
    $lnkIcon = New-AboutLink (L 'about.iconPage') $IconUrl
    $lnkCcBy = New-AboutLink (L 'about.ccby') $CcByUrl
    $creditLinks = New-Object Windows.Forms.FlowLayoutPanel
    $creditLinks.AutoSize = $true; $creditLinks.WrapContents = $false; $creditLinks.Margin = New-Object Windows.Forms.Padding(0)
    $creditLinks.Controls.AddRange(@($lnkIcon, $lnkCcBy))
    $lblDisclaimer = New-AboutText (L 'about.disclaimer') $w $false

    # Κουμπιά, στοιχισμένα δεξιά
    $btnRow = New-Object Windows.Forms.FlowLayoutPanel
    $btnRow.FlowDirection = 'RightToLeft'; $btnRow.WrapContents = $false
    $btnRow.Size = New-Object Drawing.Size($w, (P 44)); $btnRow.Margin = New-Object Windows.Forms.Padding(0, (P 16), 0, 0)
    $btnClose = New-Btn 120 'accent'; $btnClose.Text = L 'about.close'; $btnClose.DialogResult = 'OK'
    $btnLicense = New-Btn 150 ''; $btnLicense.Text = L 'about.license'
    $btnLicense.add_Click({ param($s, $e) Show-License $s.FindForm() })
    $btnRow.Controls.AddRange(@($btnClose, $btnLicense))

    $body.Controls.AddRange(@(
        $top,
        (New-AboutText (L 'about.desc') $w $false),
        (New-AboutText (L 'about.hLicense') $w $true),
        (New-AboutText (L 'about.copyright') $w $false),
        $lnkRepo,
        (New-AboutText (L 'about.hCredits') $w $true),
        (New-AboutText (L 'about.icon') $w $false),
        $creditLinks,
        (New-AboutText (L 'about.hDisclaimer') $w $true),
        $lblDisclaimer,
        $btnRow))
    $d.Controls.Add($body)

    Apply-ThemeTo $d
    $lblVer.ForeColor = $T.Muted; $lblDisclaimer.ForeColor = $T.Muted
    $linkColor = if ($T.Name -eq 'Dark') { C 110 170 255 } else { $Accent }
    foreach ($l in @($lnkRepo, $lnkIcon, $lnkCcBy)) {
        $l.LinkColor = $linkColor; $l.ActiveLinkColor = $linkColor; $l.VisitedLinkColor = $linkColor
    }
    $d.AcceptButton = $btnClose; $d.CancelButton = $btnClose
    [void]$d.ShowDialog($form)
    $d.Dispose()
}

# ============================================================
#  ΓΕΜΙΣΜΑ ΔΕΝΤΡΟΥ & ΡΥΘΜΙΣΕΩΝ
# ============================================================
foreach ($k in $GroupKeys) {
    $g = New-Object Windows.Forms.TreeNode
    $g.Text = (L "grp.$k") + '      '
    $g.Tag = "group:$k"
    $g.NodeFont = $BoldFont
    [void]$tree.Nodes.Add($g)
    $GroupNodes[$k] = $g
}
$checkedSaved = if ($Settings -and $null -ne $Settings.Checked) { @($Settings.Checked) } else { $null }
$knownSaved = if ($Settings -and $Settings.Known) { @($Settings.Known) } else { $V6Ids }
foreach ($t in $TaskMeta) {
    # Εργασίες που δεν υπήρχαν όταν αποθηκεύτηκαν οι ρυθμίσεις παίρνουν την προεπιλογή τους
    $isChecked = if ($null -ne $checkedSaved -and $knownSaved -contains $t.Id) { $checkedSaved -contains $t.Id } else { [bool]$t.Default }
    [void](Add-TaskNode $t.Id $t.Group $isChecked)
}
if ($Settings -and $Settings.Custom) {
    foreach ($c in @($Settings.Custom)) {
        if (-not $c) { continue }
        $id = "custom:$c"; $TaskNames[$id] = $c
        $isChecked = if ($null -ne $checkedSaved) { $checkedSaved -contains $id } else { $true }
        [void](Add-TaskNode $id 'custom' $isChecked)
    }
}
foreach ($g in $tree.Nodes) { Update-GroupState $g }
$tree.ExpandAll()
$tbProj.Text = if ($Settings -and $Settings.ProjectsRoot) { $Settings.ProjectsRoot } else { $DefaultProjects }
$tbKill.Text = if ($Settings -and $Settings.KillList) { $Settings.KillList } else { $DefaultKillList }
$tbRoot.Text = if ($Settings -and $Settings.ScanRoot) { $Settings.ScanRoot } else { "$env:SystemDrive\" }
$numMin.Value = if ($Settings -and $Settings.MinMB) { [math]::Min(100000, [math]::Max(1, [int]$Settings.MinMB)) } else { 200 }
$chkRecycle.Checked = if ($Settings -and $null -ne $Settings.Recycle) { [bool]$Settings.Recycle } else { $true }

# ============================================================
#  ΣΥΜΒΑΝΤΑ
# ============================================================
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 150
$timer.add_Tick({
    $m = $null; $count = 0
    while ($count -lt 500 -and $sync.Queue.TryDequeue([ref]$m)) {
        $count++
        switch ($m.T) {
            'log'      { Add-LogLine $m.D }
            'progress' {
                if ($pb.Style -ne 'Marquee') {
                    $pb.Maximum = [math]::Max(1, [int]$m.D.Max)
                    $pb.Value = [math]::Min([int]$m.D.V, $pb.Maximum)
                }
                $lblStatus.Text = $m.D.Text
            }
            'size'     {
                $SizeById[$m.D.Id] = [int64]$m.D.Bytes
                if ($NodeById.ContainsKey($m.D.Id)) { Update-NodeText $NodeById[$m.D.Id] }
                Update-SelectedTotal
            }
            'taskdone' {
                [void]$DoneIds.Add($m.D); [void]$SizeById.Remove($m.D)
                if ($NodeById.ContainsKey($m.D)) { Update-NodeText $NodeById[$m.D] }
            }
            'found'    { Add-BigResults $m.D }
            'deleted'  {
                $li = $BigItemByPath[[string]$m.D.Path]
                if ($li -and $m.D.Ok) { $lvBig.Items.Remove($li); $BigItemByPath.Remove([string]$m.D.Path) }
            }
            'done'     { $script:lastDone = $m.D }
        }
    }
    if ($script:handle -and $script:handle.IsCompleted -and $sync.Queue.IsEmpty) { Complete-Worker }
})

# --- Πλοήγηση, θέμα, γλώσσα ---
$btnNavClean.add_Click({ Show-Page 0 })
$btnNavBig.add_Click({ Show-Page 1 })
$btnNavHist.add_Click({ Show-Page 2 })
$btnTheme.add_Click({
    if ($script:Theme.Name -eq 'Dark') { Set-Theme $Themes.Light } else { Set-Theme $Themes.Dark }
    Save-Settings
})
$btnLang.add_Click({
    if ($sync.Lang -eq 'el') { Set-Language 'en' } else { Set-Language 'el' }
    Save-Settings
})
$btnAbout.add_Click({ Show-About })

# --- Σελίδα Καθαρισμός ---
$tree.add_BeforeCheck({ param($s, $e) if ($script:busy) { $e.Cancel = $true } })
$tree.add_AfterCheck({
    param($s, $e)
    if ($script:suppress) { return }
    $script:suppress = $true
    try {
        foreach ($c in $e.Node.Nodes) { $c.Checked = $e.Node.Checked }
    } finally { $script:suppress = $false }
    if ($e.Node.Parent) { Update-GroupState $e.Node.Parent }
    Update-SelectedTotal
})
$tree.add_AfterSelect({ param($s, $e) Show-Desc $e.Node })

function Set-AllChecked([scriptblock]$rule) {
    $script:suppress = $true
    foreach ($n in (Get-LeafNodes)) { $n.Checked = [bool](& $rule $n) }
    $script:suppress = $false
    foreach ($g in $tree.Nodes) { Update-GroupState $g }
    Update-SelectedTotal
}
$btnAll.add_Click({ Set-AllChecked { $true } })
$btnNone.add_Click({ Set-AllChecked { $false } })
$btnDefault.add_Click({
    $defaults = @($TaskMeta | Where-Object { $_.Default } | ForEach-Object { $_.Id })
    Set-AllChecked { param($n) $id = [string]$n.Tag; ($defaults -contains $id) -or ($id -like 'custom:*') }
})

$btnAddDir.add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = L 'dlg.addDir'
    if ($dlg.ShowDialog($form) -ne 'OK') { return }
    $p = $dlg.SelectedPath.TrimEnd('\')
    if (Test-CustomBlocked $p) {
        [void][Windows.Forms.MessageBox]::Show($form, (L 'msg.protected' $p), (L 'msg.protectedTitle'), 'OK', 'Warning')
        return
    }
    $id = "custom:$p"
    if ($NodeById.ContainsKey($id)) { return }
    $ok = [Windows.Forms.MessageBox]::Show($form, (L 'msg.addDir' $p), (L 'msg.addDirTitle'), 'YesNo', 'Warning')
    if ($ok -ne 'Yes') { return }
    $TaskNames[$id] = $p
    $n = Add-TaskNode $id 'custom' $true
    $GroupNodes['custom'].Expand()
    Update-GroupState $GroupNodes['custom']
    $tree.SelectedNode = $n
    Update-SelectedTotal
    Save-Settings
})
$btnDelDir.add_Click({
    $n = $tree.SelectedNode
    if (-not $n -or -not ([string]$n.Tag -like 'custom:*')) {
        [void][Windows.Forms.MessageBox]::Show($form, (L 'msg.selectCustom'), 'System Optimizer', 'OK', 'Information')
        return
    }
    $NodeById.Remove([string]$n.Tag); $TaskNames.Remove([string]$n.Tag)
    $n.Remove()
    Update-SelectedTotal
    Save-Settings
})

$btnProj.add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = L 'dlg.projects'
    if (Test-Path -LiteralPath $tbProj.Text) { $dlg.SelectedPath = $tbProj.Text }
    if ($dlg.ShowDialog($form) -eq 'OK') { $tbProj.Text = $dlg.SelectedPath }
})

$btnScan.add_Click({
    $ids = @(Get-LeafNodes | ForEach-Object { [string]$_.Tag })
    Add-LogLine (L 'log.scanAll')
    Start-Worker 'scan' $ids
})

$btnClean.add_Click({
    $ids = @(Get-LeafNodes | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Tag })
    if ($ids.Count -eq 0) {
        [void][Windows.Forms.MessageBox]::Show($form, (L 'msg.noTasks'), 'System Optimizer', 'OK', 'Information')
        return
    }
    $list = ($ids | ForEach-Object { '•  ' + $TaskNames[$_] }) -join "`n"
    $warn = @()
    if ($ids -contains 'killapps') { $warn += L 'warn.kill' }
    if ($ids -contains 'dism') { $warn += L 'warn.dism' }
    if ($ids -contains 'wsl') { $warn += L 'warn.wsl' }
    if ($ids -contains 'windowsold') { $warn += L 'warn.winold' }
    if (@($ids | Where-Object { $_ -like 'custom:*' }).Count) { $warn += L 'warn.custom' }
    if ($ids -contains 'chrome' -or $ids -contains 'edge') { $warn += L 'warn.browsers' }
    $r = [Windows.Forms.MessageBox]::Show($form, (L 'confirm.tasks' $list ($warn -join "`n")), (L 'confirm.title'), 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Save-Settings
    $DoneIds.Clear()
    foreach ($n in (Get-LeafNodes)) { Update-NodeText $n }
    Start-Worker 'clean' $ids
})

# --- Σελίδα Μεγάλα αρχεία ---
$btnRoot.add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = L 'dlg.root'
    if (Test-Path -LiteralPath $tbRoot.Text) { $dlg.SelectedPath = $tbRoot.Text }
    if ($dlg.ShowDialog($form) -eq 'OK') { $tbRoot.Text = $dlg.SelectedPath }
})

function Start-BigScan([string]$mode) {
    if (-not (Test-Path -LiteralPath $tbRoot.Text)) {
        [void][Windows.Forms.MessageBox]::Show($form, (L 'msg.rootMissing'), 'System Optimizer', 'OK', 'Warning')
        return
    }
    Add-BigResults @()
    $script:bigSortCol = 1; $script:bigSortDesc = $true
    Add-LogLine (L 'log.searchIn' $tbRoot.Text)
    $lblStatus.Text = L 'status.scanning'
    Save-Settings
    Start-Worker $mode @()
}
$btnFindBig.add_Click({ Start-BigScan 'bigfiles' })
$btnFindDev.add_Click({ Start-BigScan 'devdirs' })

$lvBig.add_ItemChecked({ if (-not $script:fillingBig) { Update-BigTotal } })
$lvBig.add_ColumnClick({
    param($s, $e)
    if ($script:bigSortCol -eq $e.Column) { $script:bigSortDesc = -not $script:bigSortDesc }
    else { $script:bigSortCol = $e.Column; $script:bigSortDesc = ($e.Column -eq 1 -or $e.Column -eq 2) }
    Sort-BigList
})
function Open-BigLocation {
    $li = if ($lvBig.SelectedItems.Count) { $lvBig.SelectedItems[0] } else { $null }
    if (-not $li) { return }
    Start-Process explorer.exe -ArgumentList "/select,`"$($li.Tag.Path)`""
}
$lvBig.add_DoubleClick({ Open-BigLocation })
$btnOpenLoc.add_Click({ Open-BigLocation })
$btnBigAll.add_Click({
    $script:fillingBig = $true; foreach ($li in $lvBig.Items) { $li.Checked = $true }; $script:fillingBig = $false; Update-BigTotal
})
$btnBigNone.add_Click({
    $script:fillingBig = $true; foreach ($li in $lvBig.Items) { $li.Checked = $false }; $script:fillingBig = $false; Update-BigTotal
})
$btnDelSel.add_Click({
    $sel = @($lvBig.CheckedItems | ForEach-Object { $_.Tag })
    if ($sel.Count -eq 0) {
        [void][Windows.Forms.MessageBox]::Show($form, (L 'msg.checkFirst'), 'System Optimizer', 'OK', 'Information')
        return
    }
    $sum = [int64]0; foreach ($o in $sel) { $sum += [int64]$o.Bytes }
    $nDirs = @($sel | Where-Object { $_.IsDir }).Count
    $nFiles = $sel.Count - $nDirs
    $how = @()
    if ($nFiles) { $how += L 'del.files' $nFiles $(if ($chkRecycle.Checked) { L 'del.toBin' } else { L 'del.permanent' }) }
    if ($nDirs) { $how += L 'del.dirs' $nDirs }
    $r = [Windows.Forms.MessageBox]::Show($form, (L 'del.confirm' $sel.Count (Format-Size $sum) ($how -join "`n")), (L 'del.title'), 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }
    $sync.DeleteList = $sel
    Start-Worker 'delete' @()
})

# --- Σελίδα Ιστορικό: γράφημα ---
$chart.add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $T = $script:Theme
    $g.Clear($T.Surface)
    $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
    [Windows.Forms.TextRenderer]::DrawText($g, (L 'chart.title'), $BoldFont, (New-Object Drawing.Point((P 12), (P 10))), $T.Text)
    $border = New-Object Drawing.Pen($T.Border); $g.DrawRectangle($border, 0, 0, $w - 1, $h - 1)

    $runs = @($History | Select-Object -Last 20)
    $script:chartGeom = $null
    if ($runs.Count -eq 0) {
        [Windows.Forms.TextRenderer]::DrawText($g, (L 'chart.empty'), $UiFont,
            (New-Object Drawing.Rectangle(0, 0, $w, $h)), $T.Muted, [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter')
        $border.Dispose(); return
    }
    $max = [double]0; $maxIdx = 0
    for ($i = 0; $i -lt $runs.Count; $i++) { if ([double]$runs[$i].Freed -gt $max) { $max = [double]$runs[$i].Freed; $maxIdx = $i } }
    if ($max -ge 1GB) { $div = 1GB; $unit = 'GB' } else { $div = 1MB; $unit = 'MB' }
    $top = Get-NiceMax ($max / $div)

    $L = P 64; $R = P 18; $Tp = P 44; $B = P 30
    $plotW = $w - $L - $R; $plotH = $h - $Tp - $B
    if ($plotW -lt 20 -or $plotH -lt 20) { $border.Dispose(); return }

    # Πλέγμα & άξονας (διακριτικά)
    $gridPen = New-Object Drawing.Pen($T.Grid)
    for ($k = 0; $k -le 4; $k++) {
        $y = [int]($Tp + $plotH - $plotH * $k / 4)
        if ($k -gt 0) { $g.DrawLine($gridPen, $L, $y, $w - $R, $y) }
        $lbl = ('{0:0.##} ' -f ($top * $k / 4)) + $unit
        [Windows.Forms.TextRenderer]::DrawText($g, $lbl, $SmallFont, (New-Object Drawing.Rectangle(0, ($y - (P 8)), ($L - (P 8)), (P 16))),
            $T.Muted, [Windows.Forms.TextFormatFlags]'Right, VerticalCenter')
    }
    $g.DrawLine($border, $L, $Tp + $plotH, $w - $R, $Tp + $plotH)
    $gridPen.Dispose()

    $n = $runs.Count
    $slot = $plotW / $n
    $bw = [math]::Min((P 40), $slot * 0.6)
    $labelStep = [math]::Max(1, [math]::Ceiling((P 44) / $slot))
    for ($i = 0; $i -lt $n; $i++) {
        $v = [double]$runs[$i].Freed / $div
        $bh = $plotH * ($v / $top)
        if ($v -gt 0 -and $bh -lt 2) { $bh = 2 }
        $x = $L + $slot * $i + ($slot - $bw) / 2
        $y = $Tp + $plotH - $bh
        if ($bh -gt 0) {
            $col = if ($i -eq $script:hoverIdx) { $T.BarHover } else { $T.Bar }
            $br = New-Object Drawing.SolidBrush($col)
            $path = New-TopRoundedPath $x $y $bw $bh ([math]::Min((P 4), [math]::Min($bh, $bw / 2)))
            $g.FillPath($br, $path); $path.Dispose(); $br.Dispose()
        }
        $cx = [int]($L + $slot * $i + $slot / 2)
        if (($i % $labelStep) -eq 0 -or $i -eq $n - 1) {
            $dt = ([string]$runs[$i].Date).Substring(5, 5) -replace '(\d\d)-(\d\d)', '$2/$1'
            [Windows.Forms.TextRenderer]::DrawText($g, $dt, $SmallFont,
                (New-Object Drawing.Rectangle(($cx - (P 30)), ($Tp + $plotH + (P 6)), (P 60), (P 16))), $T.Muted,
                [Windows.Forms.TextFormatFlags]'HorizontalCenter, Top')
        }
        # Άμεσες ετικέτες μόνο στη μέγιστη και στην τελευταία μπάρα
        if ($i -eq $maxIdx -or $i -eq $n - 1) {
            [Windows.Forms.TextRenderer]::DrawText($g, (Format-Size $runs[$i].Freed), $SmallFont,
                (New-Object Drawing.Rectangle(($cx - (P 45)), [int]($y - (P 18)), (P 90), (P 16))), $T.Text,
                [Windows.Forms.TextFormatFlags]'HorizontalCenter, Bottom')
        }
    }
    $border.Dispose()
    $script:chartGeom = @{ L = $L; Slot = $slot; N = $n; Tp = $Tp; PlotH = $plotH; Runs = $runs }
})

$chart.add_MouseMove({
    param($s, $e)
    $gm = $script:chartGeom
    $i = -1
    if ($gm -and $e.X -ge $gm.L -and $e.Y -ge $gm.Tp -and $e.Y -le ($gm.Tp + $gm.PlotH + (P 24))) {
        $i = [int][math]::Floor(($e.X - $gm.L) / $gm.Slot)
        if ($i -ge $gm.N) { $i = -1 }
    }
    if ($i -ne $script:hoverIdx) {
        $script:hoverIdx = $i
        $s.Invalidate()
        if ($i -ge 0) {
            $r = $gm.Runs[$i]
            $txt = L 'chart.tip' $r.Date (Format-Size $r.Freed) (Format-Size $r.Free) ('{0:hh\:mm\:ss}' -f [TimeSpan]::FromSeconds([int]$r.Seconds)) $r.Tasks
            $chartTip.Show($txt, $s, $e.X + (P 14), $e.Y + (P 14))
        } else {
            $chartTip.Hide($s)
        }
    }
})
$chart.add_MouseLeave({ $script:hoverIdx = -1; $chartTip.Hide($chart); $chart.Invalidate() })
$chart.add_Resize({ $chart.Invalidate() })

$btnHistClear.add_Click({
    if ($History.Count -eq 0) { return }
    $r = [Windows.Forms.MessageBox]::Show($form, (L 'hist.clearConfirm'), (L 'hist.title'), 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $History.Clear(); Save-History; Update-History
})

# --- Κοινά ---
$btnStop.add_Click({
    $sync.Cancel = $true
    Add-LogLine (L 'log.stop')
})

$btnLog.add_Click({
    if (Test-Path -LiteralPath $LogPath) { Start-Process notepad.exe -ArgumentList "`"$LogPath`"" }
})

$form.add_Shown({
    try { $split.SplitterDistance = P 480 } catch { }
    Set-Theme $script:Theme
    Show-Page 0
    Add-LogLine (L 'log.ready')
})

$form.add_FormClosing({
    param($s, $e)
    if ($script:busy) {
        [void][Windows.Forms.MessageBox]::Show($form, (L 'msg.busy'), 'System Optimizer', 'OK', 'Warning')
        $e.Cancel = $true
        return
    }
    Save-Settings
})

Set-Language $sync.Lang
Set-Theme $script:Theme
[void]$form.ShowDialog()
if (Test-Path -LiteralPath $sync.EmptyDir) { Remove-Item -LiteralPath $sync.EmptyDir -Recurse -Force -ErrorAction SilentlyContinue }
