param([string]$PreviewPath='', [switch]$SmokeTest, [switch]$ShowDetails)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Core.ps1')

$script:stateDirectory = Join-Path $PSScriptRoot '.state'
$script:settingsPath = Join-Path $script:stateDirectory 'settings.json'
$script:process = $null
$script:jobDirectory = ''
$script:logText = ''
$script:lastWebUrl = ''
$script:settingsDirty = $false
$script:authorName = ''
$script:authorEmail = ''
$script:lastResult = $null
$script:startupSmoke = [bool]$SmokeTest
$script:previewTarget = $PreviewPath
$script:showDetailsOnStart = [bool]$ShowDetails
. (Join-Path $PSScriptRoot 'Ui.ps1')

function Show-UiError([string]$message) {
    $statusLabel.Text='Có lỗi · Xem thêm'
    $statusLabel.ForeColor=[Drawing.Color]::Firebrick
    $detailsButton.ForeColor=[Drawing.Color]::Firebrick
    $logBox.AppendText("`r`n"+$message+"`r`n")
}

function Save-Settings {
    if ($script:startupSmoke) { return }
    try {
        [void][IO.Directory]::CreateDirectory($script:stateDirectory)
        $settings=@{ Folder=$folderBox.Text; Repository=$repoBox.Text; AuthorName=$script:authorName; AuthorEmail=$script:authorEmail }
        [IO.File]::WriteAllText($script:settingsPath,($settings | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        $script:settingsDirty=$false
    } catch { $logBox.AppendText("`nKhông lưu được cấu hình: $($_.Exception.Message)") }
}
if (Test-Path -LiteralPath $script:settingsPath) {
    try {
        $saved=[IO.File]::ReadAllText($script:settingsPath) | ConvertFrom-Json
        $folderBox.Text=[string]$saved.Folder; $repoBox.Text=[string]$saved.Repository
        $script:authorName=[string]$saved.AuthorName; $script:authorEmail=[string]$saved.AuthorEmail
    } catch { $logBox.AppendText("`nKhông đọc được cấu hình cũ. Bạn có thể nhập lại.") }
}
$folderBox.Add_TextChanged({ $script:settingsDirty=$true })
$repoBox.Add_TextChanged({
    $script:settingsDirty=$true
    if (-not $script:process) {
        try { $script:lastWebUrl=(ConvertTo-GitHubRepository $repoBox.Text).WebUrl; $openButton.Enabled=$true }
        catch { $openButton.Enabled=$false; $script:lastWebUrl='' }
    }
})
$browseButton.Add_Click({
    $dialog=New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description='Chọn thư mục gốc chứa code cần push'
    if ($folderBox.Text -and (Test-Path -LiteralPath $folderBox.Text -PathType Container)) { $dialog.SelectedPath=$folderBox.Text }
    if ($dialog.ShowDialog($form) -eq 'OK') { $folderBox.Text=$dialog.SelectedPath }
    $dialog.Dispose()
})
$openButton.Add_Click({
    try {
        $url=(ConvertTo-GitHubRepository $repoBox.Text).WebUrl
        [void][Diagnostics.Process]::Start($url)
    } catch { Show-UiError $_.Exception.Message }
})

$authorButton.Add_Click({
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text='Tác giả'; $dialog.ClientSize=New-Object Drawing.Size(360,210)
    $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false
    $dialog.Font=New-Object Drawing.Font('Segoe UI',10); $dialog.BackColor=$background
    $nameLabel=New-Object Windows.Forms.Label
    $nameLabel.Text='Tên'; $nameLabel.Location=New-Object Drawing.Point(22,16); $nameLabel.Size=New-Object Drawing.Size(316,20)
    $nameInput=New-Object Windows.Forms.TextBox
    $nameInput.Location=New-Object Drawing.Point(22,40); $nameInput.Size=New-Object Drawing.Size(316,30); $nameInput.Text=$script:authorName
    $emailLabel=New-Object Windows.Forms.Label
    $emailLabel.Text='Email'; $emailLabel.Location=New-Object Drawing.Point(22,80); $emailLabel.Size=New-Object Drawing.Size(316,20)
    $emailInput=New-Object Windows.Forms.TextBox
    $emailInput.Location=New-Object Drawing.Point(22,104); $emailInput.Size=New-Object Drawing.Size(316,30); $emailInput.Text=$script:authorEmail
    $save=New-Object Windows.Forms.Button
    $save.Text='Lưu'; $save.Location=New-Object Drawing.Point(244,158); $save.Size=New-Object Drawing.Size(94,32)
    $save.Add_Click({
        if (($nameInput.Text.Trim() -and -not $emailInput.Text.Trim()) -or ($emailInput.Text.Trim() -and -not $nameInput.Text.Trim())) {
            [void][Windows.Forms.MessageBox]::Show($dialog,'Nhập đủ tên và email, hoặc để trống cả hai.','Thông tin tác giả','OK','Warning'); return
        }
        if ($emailInput.Text.Trim() -and $emailInput.Text.Trim() -notmatch '^[^\s@<>]+@[^\s@<>]+$') {
            [void][Windows.Forms.MessageBox]::Show($dialog,'Email chưa hợp lệ.','Thông tin tác giả','OK','Warning'); return
        }
        $script:authorName=$nameInput.Text.Trim(); $script:authorEmail=$emailInput.Text.Trim()
        Save-Settings
        $dialog.DialogResult='OK'; $dialog.Close()
    })
    $dialog.Controls.AddRange(@($nameLabel,$nameInput,$emailLabel,$emailInput,$save)); $dialog.AcceptButton=$save
    [void]$dialog.ShowDialog($form); $dialog.Dispose()
})

function Set-Busy([bool]$busy) {
    foreach ($control in @($folderBox,$repoBox,$commitBox,$browseButton,$loginButton,$authorButton,$runButton)) { $control.Enabled=-not $busy }
    $openButton.Enabled=(-not $busy -and -not [string]::IsNullOrWhiteSpace($script:lastWebUrl))
    if ($busy) { $progress.Visible=$true; $progress.Style='Marquee'; $runButton.Text='Đang chạy...'; $form.UseWaitCursor=$false }
    else { $progress.Style='Continuous'; $runButton.Text='Chạy' }
}

function Start-WorkerJob([hashtable]$request) {
    Save-Settings
    $script:jobDirectory=Join-Path $script:stateDirectory ('jobs\' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($script:jobDirectory)
    $requestPath=Join-Path $script:jobDirectory 'request.json'
    [IO.File]::WriteAllText($requestPath,($request | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $script:logText=''; $logBox.Clear(); $script:lastResult=$null
    $statusLabel.Text=if ($request.Action -eq 'Login') { 'Chờ đăng nhập...' } else { 'Đang chạy...' }
    $statusLabel.ForeColor=$ink
    $detailsButton.ForeColor=$muted
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $workerPath=Join-Path $PSScriptRoot 'Worker.ps1'
    $info.Arguments='-NoProfile -ExecutionPolicy Bypass -File ' + (ConvertTo-NativeArgument $workerPath) + ' -RequestPath ' + (ConvertTo-NativeArgument $requestPath)
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.WorkingDirectory=$PSScriptRoot
    $script:process=[Diagnostics.Process]::Start($info)
    Set-Busy $true
    $timer.Start()
}

$timer=New-Object Windows.Forms.Timer
$timer.Interval=350
$timer.Add_Tick({
    if (-not $script:process) { return }
    try {
        $logPath=Join-Path $script:jobDirectory 'progress.log'
        if (Test-Path -LiteralPath $logPath) {
            try { $current=[IO.File]::ReadAllText($logPath) } catch { $current=$null }
            if ($null -ne $current -and $current -ne $script:logText) {
                $script:logText=$current; $logBox.Text=$current; $logBox.SelectionStart=$logBox.TextLength; $logBox.ScrollToCaret()
            }
        }
        if ($script:process.HasExited) {
            $timer.Stop()
            $exitCode=$script:process.ExitCode
            $script:process.Dispose(); $script:process=$null
            Set-Busy $false
            $resultPath=Join-Path $script:jobDirectory 'result.json'
            if (Test-Path -LiteralPath $resultPath) {
                $result=[IO.File]::ReadAllText($resultPath) | ConvertFrom-Json
                $script:lastResult=$result
                if ($result.Success) {
                    $statusLabel.Text=if ($result.Action -eq 'Login') { 'Đã đăng nhập' } else { 'Đã push ✓' }
                    $statusLabel.ForeColor=$green; $progress.Value=100
                    if ($result.Action -eq 'Push') { $script:lastWebUrl=$result.WebUrl; $openButton.Enabled=$true }
                    else { $logBox.AppendText("`r`n" + $result.Message) }
                } else {
                    $progress.Value=0
                    Show-UiError $result.Message
                }
            } else {
                Show-UiError "Tiến trình dừng bất thường (mã $exitCode). Bạn có thể chạy lại."
            }
        }
    } catch {
        # A writer may briefly hold the log. Retry on the next tick while a worker is running.
        if (-not $script:process) { $timer.Stop(); Show-UiError 'Không đọc được kết quả. Xem log trong folder .state\jobs.'; Set-Busy $false }
    }
})

$runButton.Add_Click({
    try {
        $repo=ConvertTo-GitHubRepository $repoBox.Text
        $state=Get-RepositoryState $folderBox.Text.Trim()
        $approved=$false
        if ($state.Origin -and -not (Test-SameRemote $state.Origin $repo.Url)) {
            $originDisplay=$state.Origin -replace '(https?://)[^\s/@]+@','$1[ẩn]@'
            $message="Folder này đang kết nối với:`r`n$originDisplay`r`n`r`nĐổi sang repo sau và push code?`r`n$($repo.WebUrl)"
            if ([Windows.Forms.MessageBox]::Show($form,$message,'Xác nhận đổi repo đích','YesNo','Warning') -ne 'Yes') { return }
            $approved=$true
        }
        $script:lastWebUrl=$repo.WebUrl
        Start-WorkerJob @{ Action='Push'; Folder=$state.Folder; RemoteUrl=$repo.Url; CommitMessage=$commitBox.Text; AuthorName=$script:authorName; AuthorEmail=$script:authorEmail; ApproveRemoteChange=$approved }
    } catch { Show-UiError $_.Exception.Message }
})
$loginButton.Add_Click({
    try { [void](Get-GitExecutable); Start-WorkerJob @{ Action='Login' } }
    catch { Show-UiError $_.Exception.Message }
})
$form.Add_FormClosing({
    param($sender,$eventArgs)
    if ($script:process -and -not $script:process.HasExited) {
        $eventArgs.Cancel=$true
        [void][Windows.Forms.MessageBox]::Show($form,'Git đang chạy. Chờ hoàn tất hoặc hết thời gian chờ rồi đóng tool để tránh ngắt thao tác giữa chừng.','Đang xử lý','OK','Information')
    } elseif ($script:settingsDirty) { Save-Settings }
})
$form.Add_Shown({
    if ($script:showDetailsOnStart) { Set-DetailsVisible $true }
    if ($script:startupSmoke) {
        try {
            if ($script:previewTarget) {
                $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
                $form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
                $bitmap.Save($script:previewTarget,[Drawing.Imaging.ImageFormat]::Png); $bitmap.Dispose()
            }
            $script:smokeControls=$form.Controls.Count
        } finally { $form.Close() }
    }
})
try { [void](Get-GitExecutable) }
catch { Show-UiError $_.Exception.Message }
try { $script:lastWebUrl=(ConvertTo-GitHubRepository $repoBox.Text).WebUrl; $openButton.Enabled=$true } catch {}
[void]$form.ShowDialog()
$timer.Dispose(); $form.Dispose()
if ($SmokeTest) { Write-Output "GUI smoke test passed: $script:smokeControls controls; preview: $PreviewPath" }
