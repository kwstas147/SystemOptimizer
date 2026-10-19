// Launcher του Ultimate System Optimizer.
// Το SystemOptimizer.ps1 είναι ενσωματωμένο ως resource. Ο launcher ζητά δικαιώματα
// Διαχειριστή, γράφει το script στο %LOCALAPPDATA%\SystemOptimizer και το εκτελεί με το
// Windows PowerShell ακριβώς όπως το Start-Optimizer.bat. Οι ρυθμίσεις, το ιστορικό και το
// log γράφονται δίπλα στο .exe (παράμετρος -DataDir).
//
// Build: build-exe.bat (csc.exe του .NET Framework 4, υπάρχει ήδη στα Windows).

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;

[assembly: AssemblyTitle("Ultimate System Optimizer")]
[assembly: AssemblyProduct("Ultimate System Optimizer")]
[assembly: AssemblyDescription("Windows cleanup tool")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Kwstas (kwstas147). MIT License.")]
[assembly: AssemblyVersion("7.0.0.0")]
[assembly: AssemblyFileVersion("7.0.0.0")]

static class Launcher
{
    const string Title = "System Optimizer";
    const string ScriptName = "SystemOptimizer.ps1";

    [STAThread]
    static int Main()
    {
        Assembly asm = Assembly.GetExecutingAssembly();
        string exePath = asm.Location;
        string exeDir = Path.GetDirectoryName(exePath).TrimEnd('\\');

        if (!IsAdmin())
        {
            try
            {
                Process.Start(new ProcessStartInfo(exePath) { UseShellExecute = true, Verb = "runas" });
            }
            catch (Exception)
            {
                // Ο χρήστης πάτησε «Όχι» στο UAC
                MessageBox.Show("Απαιτούνται δικαιώματα Διαχειριστή.\nAdministrator rights are required.",
                    Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            return 0;
        }

        try
        {
            string workDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SystemOptimizer");
            Directory.CreateDirectory(workDir);
            string script = Path.Combine(workDir, ScriptName);
            using (Stream src = asm.GetManifestResourceStream(ScriptName))
            using (FileStream dst = File.Create(script))
            {
                src.CopyTo(dst);
            }

            // Από 32-bit διεργασία σε 64-bit Windows, το Sysnative δίνει το 64-bit PowerShell
            string sysDir = Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess ? "Sysnative" : "System32";
            string powershell = Path.Combine(
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), sysDir),
                @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershell)) powershell = "powershell.exe";

            ProcessStartInfo psi = new ProcessStartInfo(powershell);
            psi.Arguments = string.Format(
                "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"{0}\" -DataDir \"{1}\" -IconPath \"{2}\"",
                script, exeDir, exePath);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = exeDir;
            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    static bool IsAdmin()
    {
        return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
    }
}
