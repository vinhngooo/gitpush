param([Parameter(Mandatory=$true)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$utf8 = New-Object Text.UTF8Encoding($false)
$jobFolder = Split-Path -Parent $RequestPath
$logPath = Join-Path $jobFolder 'progress.log'
$resultPath = Join-Path $jobFolder 'result.json'
function Write-ProgressLine([string]$message) {
    [IO.File]::AppendAllText($logPath, ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $message) + "`r`n", $utf8)
}
function Get-FriendlyError([string]$message) {
    # Remove embedded credentials from diagnostics inherited from an existing remote/config.
    $message = $message -replace '(https?://)[^\s/@]+@', '$1[ẩn]@'
    if ($message -match 'non-fast-forward|fetch first|rejected.*stale') { return "GitHub đã có commit mới. Đồng bộ repo rồi thử lại. Commit trên máy vẫn được giữ.`r`n`r`n$message" }
    if ($message -match 'Authentication failed|could not read Username|Repository not found|Permission.*denied|403|401') { return "Không có quyền truy cập repo. Kiểm tra link và bấm Đăng nhập GitHub bằng tài khoản có quyền ghi.`r`n`r`n$message" }
    if ($message -match 'protected branch|GH006|GH013|repository rule') { return "GitHub yêu cầu Pull Request hoặc có quy tắc bảo vệ nhánh. Đẩy lên nhánh được phép rồi tạo Pull Request.`r`n`r`n$message" }
    if ($message -match 'Could not resolve host|Failed to connect|unable to access') { return "Không kết nối được GitHub. Kiểm tra Internet, proxy hoặc VPN rồi thử lại.`r`n`r`n$message" }
    if ($message -match 'exceeds GitHub.*limit|file size limit|GH001') { return "Có file vượt giới hạn GitHub. Dùng Git LFS hoặc bỏ file lớn khỏi commit rồi thử lại.`r`n`r`n$message" }
    return $message
}
try {
    $request = [IO.File]::ReadAllText($RequestPath) | ConvertFrom-Json
    if ($request.Action -eq 'Login') {
        Write-ProgressLine 'Đang mở trình duyệt đăng nhập GitHub. Hoàn tất đăng nhập trong trình duyệt...'
        [void](Invoke-GitCommand $PSScriptRoot @('credential-manager','github','login','--browser'))
        $result = @{ Success=$true; Action='Login'; Message='Đăng nhập GitHub thành công. Bạn có thể bấm Chạy để push code.' }
    } else {
        $pushed = Invoke-ProjectPush -Folder $request.Folder -RemoteUrl $request.RemoteUrl -CommitMessage $request.CommitMessage -AuthorName $request.AuthorName -AuthorEmail $request.AuthorEmail -ApproveRemoteChange:([bool]$request.ApproveRemoteChange) -OnProgress ${function:Write-ProgressLine}
        $result = @{ Success=$true; Action='Push'; Branch=$pushed.Branch; Committed=$pushed.Committed; Message="Đã push thành công nhánh $($pushed.Branch)."; WebUrl=(ConvertTo-GitHubRepository $request.RemoteUrl).WebUrl }
    }
} catch {
    $message = Get-FriendlyError $_.Exception.Message
    Write-ProgressLine ('DỪNG: ' + $message)
    $result = @{ Success=$false; Action='Error'; Message=$message }
}
$json = $result | ConvertTo-Json -Depth 4
$temporaryResult = $resultPath + '.tmp'
[IO.File]::WriteAllText($temporaryResult, $json, $utf8)
Move-Item -LiteralPath $temporaryResult -Destination $resultPath -Force
if (-not $result.Success) { exit 1 }
