<div align="center">

<img src="Cleaner_icon-icons.com_53211.png" alt="Ultimate System Optimizer" width="96">

# Ultimate System Optimizer

**Καθαρισμός Windows για developers, με γραφικό περιβάλλον: διαλέγετε με κουτάκια τι θα καθαριστεί.**

![Version](https://img.shields.io/badge/version-7.0-2ea44f)
![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![Languages](https://img.shields.io/badge/UI-Ελληνικά%20%7C%20English-555)

**Ελληνικά** · [English](#english)

</div>

---

## Γιατί

Τα εργαλεία ανάπτυξης γεμίζουν τον δίσκο χωρίς να το καταλάβετε. Caches του Gradle, φάκελοι build σε Flutter και Android projects, `node_modules` που ξεχάσατε, δίσκοι WSL που μεγαλώνουν και δεν μικραίνουν ποτέ. Το **Ultimate System Optimizer** τα συγκεντρώνει σε ένα παράθυρο, μαζί με τον κλασικό καθαρισμό των Windows. Για κάθε επιλογή εξηγεί τι ακριβώς διαγράφεται και τι μένει ανέγγιχτο.

## Χαρακτηριστικά

- **33 εργασίες καθαρισμού σε 5 ομάδες**, με αναλυτική περιγραφή για καθεμία.
- **Σάρωση μεγέθους**: βλέπετε πόσο χώρο πιάνει κάθε επιλογή πριν διαγράψετε οτιδήποτε.
- **Δικοί σας φάκελοι**: προσθέτετε όποιον φάκελο θέλετε να αδειάζει.
- **Μεγάλα αρχεία & node_modules**: βρίσκει τα μεγαλύτερα αρχεία του δίσκου και ξεχασμένους φακέλους `node_modules`, `venv`, `__pycache__`, `.next` κ.ά. Τα αρχεία μπορούν να πάνε στον Κάδο.
- **Ιστορικό**: γράφημα και λίστα με τον χώρο που ελευθερώθηκε σε κάθε καθαρισμό.
- **Ασφαλής σειρά εκτέλεσης**: ο τερματισμός εφαρμογών τρέχει πρώτος και οι αργές εργασίες (DISM, WSL) τελευταίες. Ο καθαρισμός σταματά οποιαδήποτε στιγμή.
- **Προειδοποιήσεις** πριν από ενέργειες που δεν αναιρούνται (Windows.old, τερματισμός εφαρμογών, DISM, WSL, browsers).
- **Δίγλωσσο περιβάλλον** (Ελληνικά / English) και **φωτεινό / σκοτεινό θέμα**.
- **Αρχείο καταγραφής** με κάθε διαγραφή, για πλήρη διαφάνεια.
- Αποθηκεύει τις επιλογές σας για την επόμενη φορά.

## Τι καθαρίζει

Με ✅ σημειώνονται οι εργασίες που είναι τικαρισμένες από προεπιλογή.

<details>
<summary><b>Windows</b> (11 εργασίες)</summary>

| Εργασία | Προεπ. | Σημείωση |
|---|:---:|---|
| Εκκαθάριση Δίσκου (`cleanmgr /sagerun`) | ✅ | Temp, Windows Update Cleanup, logs, Delivery Optimization, thumbnails κ.ά. |
| Cache Windows Update | ✅ | Σταματά προσωρινά τις υπηρεσίες `wuauserv` / `BITS` |
| `%TEMP%` χρήστη | ✅ | Τα αρχεία που είναι σε χρήση παραλείπονται |
| `Windows\Temp` | ✅ | |
| Κάδος Ανακύκλωσης | ✅ | Οριστική διαγραφή |
| Crash dumps & αναφορές WER | ✅ | |
| Cache DNS | ✅ | Δεν ελευθερώνει χώρο, βοηθά σε προβλήματα σύνδεσης |
| Windows.old | | ⚠️ Μετά δεν γίνεται επιστροφή στην προηγούμενη έκδοση |
| Prefetch | | |
| DISM Component Cleanup | | Αργό (10-20 λεπτά) |
| Event logs (System, Application) | | Χάνεται το ιστορικό σφαλμάτων |

</details>

<details>
<summary><b>IDE</b> (6 εργασίες)</summary>

| Εργασία | Προεπ. |
|---|:---:|
| Cursor: caches | ✅ |
| VS Code: caches | ✅ |
| Antigravity & Hermes: caches | ✅ |
| JetBrains IDEs: caches | ✅ |
| Παλιές εκδόσεις Android Studio (κρατά μόνο τη νεότερη) | ✅ |
| Dart Analysis Server (`.dartServer`) | ✅ |

</details>

<details>
<summary><b>Ανάπτυξη</b> (10 εργασίες)</summary>

| Εργασία | Προεπ. | Σημείωση |
|---|:---:|---|
| Flutter / Android projects: φάκελοι build | ✅ | Ο πηγαίος κώδικας δεν αγγίζεται |
| Gradle: caches, daemons, wrappers | ✅ | Το επόμενο build ξανακατεβάζει dependencies |
| npm / pnpm cache | ✅ | |
| Yarn cache | ✅ | |
| pip cache | ✅ | |
| Arduino15 staging | ✅ | |
| Android models (`.android\models`) | ✅ | |
| NuGet packages & cache | | |
| Flutter / Dart pub-cache | | Μετά χρειάζεται `flutter pub get` |
| Συμπίεση δίσκων WSL / Docker | | Δεν διαγράφει δεδομένα, αργό |

</details>

<details>
<summary><b>Browsers</b> (2 εργασίες)</summary>

| Εργασία | Προεπ. | Σημείωση |
|---|:---:|---|
| Google Chrome: cache | | Κωδικοί, ιστορικό, σελιδοδείκτες και cookies **δεν** αγγίζονται |
| Microsoft Edge: cache | | Όπως παραπάνω |

</details>

<details>
<summary><b>Εφαρμογές</b> (4 εργασίες)</summary>

| Εργασία | Προεπ. | Σημείωση |
|---|:---:|---|
| Discord: cache (και PTB / Canary) | ✅ | Οι συνομιλίες δεν αγγίζονται |
| Spotify: cache | ✅ | Τα offline τραγούδια δεν αγγίζονται |
| Microsoft Teams: cache | ✅ | |
| Τερματισμός εφαρμογών | | ⚠️ Κλείνουν χωρίς αποθήκευση. Η λίστα ορίζεται στις Ρυθμίσεις |

</details>

## Απαιτήσεις

- Windows 10 ή 11
- Windows PowerShell 5.1 (υπάρχει ήδη στα Windows)
- Δικαιώματα Διαχειριστή (η εφαρμογή τα ζητά μόνη της μέσω UAC)

## Εγκατάσταση και εκκίνηση

**Επιλογή Α: εκτελέσιμο**
1. Κατεβάστε το `SystemOptimizer.exe`.
2. Διπλό κλικ και «Ναι» στο UAC. Το `.exe` περιέχει το script και δεν χρειάζεται άλλα αρχεία.

**Επιλογή Β: από τον κώδικα**
1. Κλωνοποιήστε το repo ή κατεβάστε τα `SystemOptimizer.ps1` και `Start-Optimizer.bat` στον ίδιο φάκελο.
2. Διπλό κλικ στο `Start-Optimizer.bat` και «Ναι» στο UAC.

```powershell
git clone https://github.com/kwstas147/SystemOptimizer.git
cd SystemOptimizer
.\Start-Optimizer.bat
```

> Το `SystemOptimizer.ps1` είναι αποθηκευμένο ως **UTF-8 με BOM**. Κρατήστε την κωδικοποίηση αν το επεξεργαστείτε, αλλιώς τα ελληνικά θα εμφανίζονται χαλασμένα στο PowerShell 5.1.

## Χρήση

1. **Καθαρισμός**: τικάρετε ό,τι θέλετε. Πατήστε «Σάρωση μεγέθους» για να δείτε τα μεγέθη και μετά ξεκινήστε τον καθαρισμό.
2. **Μεγάλα αρχεία & node_modules**: επιλέξτε φάκελο και ελάχιστο μέγεθος, κάντε αναζήτηση, τικάρετε και διαγράψτε.
3. **Ιστορικό**: δείτε πόσο χώρο έχετε κερδίσει συνολικά.
4. **Ρυθμίσεις**: ορίστε τον φάκελο των projects, τη λίστα εφαρμογών προς τερματισμό και τον φάκελο αναζήτησης.

## Αρχεία που δημιουργούνται

| Αρχείο | Περιεχόμενο |
|---|---|
| `optimizer_log.txt` | Αναλυτικό log κάθε καθαρισμού |
| `SystemOptimizer.settings.json` | Επιλογές, γλώσσα, θέμα, ρυθμίσεις |
| `SystemOptimizer.history.json` | Ιστορικό καθαρισμών |

Τα αρχεία γράφονται δίπλα στο script. Αν ο φάκελος δεν επιτρέπει εγγραφή, το log πηγαίνει στο `%TEMP%` και τα JSON στο `%LOCALAPPDATA%`. Και τα τρία περιέχουν διαδρομές του υπολογιστή σας και εξαιρούνται από το git μέσω του `.gitignore`.

## Ασφάλεια

- Ο πηγαίος κώδικας των projects, οι κωδικοί και τα cookies των browsers, οι συνομιλίες και τα offline δεδομένα των εφαρμογών **δεν αγγίζονται ποτέ**.
- Οι περισσότερες διαγραφές είναι **οριστικές**. Μόνο τα αρχεία της σελίδας «Μεγάλα αρχεία» μπορούν να πάνε στον Κάδο.
- Κλείστε τα IDE, τους browsers και τις εφαρμογές πριν από τον καθαρισμό, για να μη μείνουν κλειδωμένα αρχεία.
- Ο κώδικας είναι ένα ενιαίο, αναγνώσιμο script PowerShell. Μπορείτε να ελέγξετε τι κάνει πριν το εκτελέσετε.

## Δημιουργία δικού σας .exe (προαιρετικά)

```powershell
Install-Module ps2exe -Scope CurrentUser
Invoke-ps2exe .\SystemOptimizer.ps1 .\SystemOptimizer.exe -noConsole -requireAdmin -STA -iconFile .\SystemOptimizer.ico
```

---

<a id="english"></a>

## English

**A Windows clean-up tool for developers, with a GUI: tick what you want cleaned.**

### Why

Development tools quietly fill your disk: Gradle caches, build folders in Flutter and Android projects, forgotten `node_modules`, WSL disks that grow and never shrink. **Ultimate System Optimizer** gathers all of them in one window, next to the classic Windows clean-up. Every option explains exactly what gets deleted and what is left untouched.

### Features

- **33 clean-up tasks in 5 groups** (Windows, IDEs, Development, Browsers, Apps), each with a detailed description.
- **Size scan**: see how much space each option takes before deleting anything.
- **Custom folders**: add any folder you want emptied.
- **Large files & node_modules**: finds the largest files on a drive and forgotten `node_modules`, `venv`, `__pycache__`, `.next` folders and more. Files can optionally go to the Recycle Bin.
- **History**: chart and list of the space freed by each clean-up.
- **Safe execution order**: closing apps runs first and slow tasks (DISM, WSL) run last. You can stop at any time.
- **Warnings** before actions that cannot be undone (Windows.old, closing apps, DISM, WSL, browsers).
- **Bilingual UI** (Ελληνικά / English) and **light / dark theme**.
- **Detailed log** of every deletion, and your choices are remembered.

### Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built into Windows)
- Administrator rights (requested automatically through UAC)

### Getting started

**Option A: executable.** Download `SystemOptimizer.exe`, double-click it and accept the UAC prompt. The `.exe` contains the script and needs no other files.

**Option B: from source.** Put `SystemOptimizer.ps1` and `Start-Optimizer.bat` in the same folder, double-click `Start-Optimizer.bat` and accept the UAC prompt.

```powershell
git clone https://github.com/kwstas147/SystemOptimizer.git
cd SystemOptimizer
.\Start-Optimizer.bat
```

> `SystemOptimizer.ps1` is saved as **UTF-8 with BOM**. Keep that encoding when editing it, or the Greek text will break in PowerShell 5.1.

### Generated files

`optimizer_log.txt`, `SystemOptimizer.settings.json` and `SystemOptimizer.history.json` are written next to the script. If that folder is not writable, the log goes to `%TEMP%` and the JSON files go to `%LOCALAPPDATA%`. They contain paths from your machine and are excluded from git through `.gitignore`.

### Safety

- Project source code, browser passwords and cookies, chats and offline app data are **never touched**.
- Most deletions are **permanent**. Only files on the "Large files" page can go to the Recycle Bin.
- Close IDEs, browsers and apps before cleaning so no files stay locked.
- The whole tool is a single, readable PowerShell script, so you can review it before running it.
