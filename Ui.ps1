# Compact Windows Forms layout; project actions live in App.ps1.
$navy=[Drawing.Color]::FromArgb(25,34,47)
$green=[Drawing.Color]::FromArgb(29,132,91)
$ink=[Drawing.Color]::FromArgb(35,44,56)
$muted=[Drawing.Color]::FromArgb(113,121,132)
$background=[Drawing.Color]::FromArgb(248,249,251)
$border=[Drawing.Color]::FromArgb(222,226,232)

$form=New-Object Windows.Forms.Form
$form.Text='GitHub Push'
$form.ClientSize=New-Object Drawing.Size(460,242)
$form.StartPosition='CenterScreen'
$form.FormBorderStyle='FixedSingle'
$form.MaximizeBox=$false
$form.BackColor=$background
$form.Font=New-Object Drawing.Font('Segoe UI',9.5)
$form.AutoScaleMode='Dpi'
$form.Icon=[Drawing.SystemIcons]::Application

function New-Label([string]$text,[int]$x,[int]$y,[int]$width,[int]$height=20,$parent=$form) {
    $label=New-Object Windows.Forms.Label
    $label.Text=$text; $label.Location=New-Object Drawing.Point($x,$y); $label.Size=New-Object Drawing.Size($width,$height)
    $label.ForeColor=$muted
    $parent.Controls.Add($label)
    return $label
}
function New-TextBox([int]$x,[int]$y,[int]$width,$parent=$form) {
    $box=New-Object Windows.Forms.TextBox
    $box.Location=New-Object Drawing.Point($x,$y); $box.Size=New-Object Drawing.Size($width,29)
    $box.AutoSize=$false; $box.Font=New-Object Drawing.Font('Segoe UI',10)
    $box.ForeColor=$ink; $box.BorderStyle='FixedSingle'
    $parent.Controls.Add($box)
    return $box
}
function New-Button([string]$text,[int]$x,[int]$y,[int]$width,[int]$height=30,$parent=$form) {
    $button=New-Object Windows.Forms.Button
    $button.Text=$text; $button.Location=New-Object Drawing.Point($x,$y); $button.Size=New-Object Drawing.Size($width,$height)
    $button.FlatStyle='Flat'; $button.FlatAppearance.BorderColor=$border
    $button.BackColor=[Drawing.Color]::White; $button.ForeColor=$ink; $button.Cursor='Hand'
    $parent.Controls.Add($button)
    return $button
}

$folderLabel=New-Label 'Folder' 20 16 300
$folderBox=New-TextBox 20 41 325
$browseButton=New-Button 'Chọn...' 354 40 86
$repoLabel=New-Label 'Link GitHub' 20 86 300
$repoBox=New-TextBox 20 111 420
$runButton=New-Button 'Chạy' 20 155 420 40
$runButton.BackColor=$green; $runButton.ForeColor=[Drawing.Color]::White
$runButton.Font=New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
$runButton.FlatAppearance.BorderSize=0
$form.AcceptButton=$runButton

$progress=New-Object Windows.Forms.ProgressBar
$progress.Location=New-Object Drawing.Point(20,198); $progress.Size=New-Object Drawing.Size(420,3)
$progress.Visible=$false
$form.Controls.Add($progress)
$statusLabel=New-Label 'Sẵn sàng' 20 213 280
$statusLabel.AutoEllipsis=$true; $statusLabel.Font=New-Object Drawing.Font('Segoe UI',9)
$detailsButton=New-Button 'Xem thêm ▾' 326 207 114 28
$detailsButton.FlatAppearance.BorderSize=0; $detailsButton.BackColor=$background; $detailsButton.ForeColor=$muted

$detailsPanel=New-Object Windows.Forms.Panel
$detailsPanel.Location=New-Object Drawing.Point(0,242); $detailsPanel.Size=New-Object Drawing.Size(460,274)
$detailsPanel.Visible=$false
$form.Controls.Add($detailsPanel)
$separator=New-Object Windows.Forms.Panel
$separator.Location=New-Object Drawing.Point(20,0); $separator.Size=New-Object Drawing.Size(420,1); $separator.BackColor=$border
$detailsPanel.Controls.Add($separator)
$logBox=New-Object Windows.Forms.TextBox
$logBox.Multiline=$true; $logBox.ScrollBars='Vertical'
$logBox.Location=New-Object Drawing.Point(20,15); $logBox.Size=New-Object Drawing.Size(420,131)
$logBox.BackColor=$navy; $logBox.ForeColor=[Drawing.Color]::FromArgb(220,232,242)
$logBox.Font=New-Object Drawing.Font('Consolas',9); $logBox.ReadOnly=$true; $logBox.BorderStyle='None'
$detailsPanel.Controls.Add($logBox)
$commitLabel=New-Label 'Commit' 20 159 300 20 $detailsPanel
$commitBox=New-TextBox 20 184 420 $detailsPanel
$loginButton=New-Button 'Đăng nhập' 20 229 136 30 $detailsPanel
$authorButton=New-Button 'Tác giả' 166 229 120 30 $detailsPanel
$openButton=New-Button 'Mở GitHub ↗' 296 229 144 30 $detailsPanel
$openButton.Enabled=$false

function Set-DetailsVisible([bool]$visible) {
    $form.SuspendLayout()
    if ($visible) {
        $form.ClientSize=New-Object Drawing.Size($form.ClientSize.Width,($detailsPanel.Top+$detailsPanel.Height))
        $detailsPanel.Visible=$true
        $detailsButton.Text='Thu gọn ▴'
    } else {
        $detailsPanel.Visible=$false
        $form.ClientSize=New-Object Drawing.Size($form.ClientSize.Width,$detailsPanel.Top)
        $detailsButton.Text='Xem thêm ▾'
    }
    $form.ResumeLayout()
}
$detailsButton.Add_Click({ Set-DetailsVisible (-not $detailsPanel.Visible) })
