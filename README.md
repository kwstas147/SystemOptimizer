# Ultimate System Optimizer v7 (GUI)

**Ελληνικά** · [English](#english)

Γραφική έκδοση του `optimizer.bat`: τικάρετε ό,τι θέλετε να καθαριστεί.

## Εκκίνηση
1. Βάλτε τα `SystemOptimizer.ps1` και `Start-Optimizer.bat` στον ίδιο φάκελο.
2. Διπλό κλικ στο `Start-Optimizer.bat` και «Ναι» στο UAC.

## Σελίδες
- **Καθαρισμός**: κουτάκια ανά ομάδα, «Σάρωση μεγέθους», δικοί σας φάκελοι.
- **Μεγάλα αρχεία & node_modules**: βρίσκει τα μεγαλύτερα αρχεία ή ξεχασμένα node_modules / venv και τα διαγράφει (τα αρχεία προαιρετικά στον Κάδο).
- **Ιστορικό**: γράφημα και λίστα με τον χώρο που ελευθερώθηκε σε κάθε καθαρισμό.

Στην κεφαλίδα: αλλαγή γλώσσας (Ελληνικά / English) και θέματος (φωτεινό / σκοτεινό).

Αρχεία που δημιουργούνται δίπλα στο script: `optimizer_log.txt`, `SystemOptimizer.settings.json`, `SystemOptimizer.history.json`.

## Μετατροπή σε .exe (προαιρετικά)
```powershell
Install-Module ps2exe -Scope CurrentUser
Invoke-ps2exe .\SystemOptimizer.ps1 .\SystemOptimizer.exe -noConsole -requireAdmin -STA
```

---

## English

A GUI version of `optimizer.bat`: tick what you want cleaned.

**Run:** put `SystemOptimizer.ps1` and `Start-Optimizer.bat` in the same folder, double-click `Start-Optimizer.bat` and accept the UAC prompt.

**Pages**
- **Clean up**: grouped checkboxes, "Scan sizes", your own folders.
- **Large files & node_modules**: finds the largest files or forgotten node_modules / venv folders and deletes them (files optionally to the Recycle Bin).
- **History**: chart and list of the space freed by each clean-up.

The header has a language switch (Ελληνικά / English) and a light / dark theme switch.
