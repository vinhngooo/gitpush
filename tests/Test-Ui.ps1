$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$uiPath=Join-Path (Split-Path $PSScriptRoot) 'Ui.ps1'
if (-not (Test-Path -LiteralPath $uiPath)) { throw 'Compact UI is missing: details cannot be collapsed yet.' }
. $uiPath
function Assert($condition,[string]$message) { if (-not $condition) { throw $message } }
try {
    $form.Opacity=0
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    $compactHeight=$form.ClientSize.Height
    Assert ($form.ClientSize.Width -le 500 -and $compactHeight -le 280) 'Default window is not compact'
    Assert ($folderBox.Visible -and $repoBox.Visible -and $runButton.Visible) 'Essential inputs are hidden'
    Assert (-not $detailsPanel.Visible -and -not $loginButton.Visible -and -not $logBox.Visible) 'Details are visible by default'
    $folderBox.Text='C:\Dự án thử nghiệm'
    $repoBox.Text='https://github.com/example/project'
    $logBox.Text="Đang chạy...`r`nĐã xong"
    $detailsButton.PerformClick()
    Assert ($detailsPanel.Visible -and $logBox.Visible) 'Show more does not reveal progress'
    Assert ($form.ClientSize.Height -gt $compactHeight) 'Expanded window does not fit details'
    $runButton.Enabled=$false
    $detailsButton.PerformClick()
    Assert (-not $detailsPanel.Visible -and $form.ClientSize.Height -eq $compactHeight) 'Collapse does not restore small window'
    Assert (-not $runButton.Enabled) 'Toggling details re-enabled a busy Run button'
    $detailsButton.PerformClick()
    Assert ($logBox.Text -eq "Đang chạy...`r`nĐã xong") 'Toggling lost progress history'
    Assert ($folderBox.Text -eq 'C:\Dự án thử nghiệm' -and $repoBox.Text -eq 'https://github.com/example/project') 'Toggling lost project inputs'
    Write-Output 'PASS compact UI: small by default; details toggle preserves inputs, logs and busy state.'
} finally { $form.Close(); $form.Dispose() }
