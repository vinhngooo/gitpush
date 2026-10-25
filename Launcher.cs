using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(folder, "App.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Không tìm thấy App.ps1. Hãy giải nén toàn bộ folder GitHubPushTool trước khi mở ứng dụng.", "GitHub Push Tool", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        try
        {
            var info = new ProcessStartInfo();
            info.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            info.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + script + "\"";
            info.WorkingDirectory = folder;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardError = true;
            using (Process process = Process.Start(info))
            {
                string error = process.StandardError.ReadToEnd();
                process.WaitForExit();
                if (process.ExitCode != 0)
                    MessageBox.Show("Không mở được ứng dụng.\r\n\r\n" + error, "GitHub Push Tool", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        catch (Exception exception)
        {
            MessageBox.Show(exception.Message, "GitHub Push Tool", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
