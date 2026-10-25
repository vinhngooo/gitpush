# Compatible with Windows PowerShell 5.1. Dot-source this file to use the engine.
Set-StrictMode -Version 2.0

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW/CRT quoting. Never pass user input to cmd /c.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Get-GitExecutable {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in @("$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'Chưa tìm thấy Git. Cài Git for Windows từ https://git-scm.com/download/win rồi mở lại tool.'
}

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Folder,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [switch]$AllowFailure,
        [int]$TimeoutSeconds=600
    )
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Get-GitExecutable
    $info.WorkingDirectory = $Folder
    # The user selected this folder to operate on. Trust that exact path only
    # for this Git process, including repositories created by the app sandbox.
    # Reset inherited broad entries; do not write safe.directory to global config.
    $trustedFolder=[IO.Path]::GetFullPath($Folder).Replace('\','/')
    $scopedArguments=@('-c','safe.directory=','-c',('safe.directory='+$trustedFolder))+$Arguments
    $info.Arguments = (($scopedArguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    # Credential Manager may open its GUI/browser; terminal prompts cannot hang a hidden worker.
    $info.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $info.EnvironmentVariables['GCM_GUI_PROMPT'] = 'true'
    $info.EnvironmentVariables['GIT_PAGER'] = 'cat'
    foreach ($variable in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_NAMESPACE','GIT_PREFIX')) {
        $info.EnvironmentVariables.Remove($variable)
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # Kill only the process tree started by this invocation, including a waiting credential helper.
            $killer = New-Object Diagnostics.ProcessStartInfo
            $killer.FileName = "$env:SystemRoot\System32\taskkill.exe"
            $killer.Arguments = '/PID ' + $process.Id + ' /T /F'
            $killer.UseShellExecute = $false
            $killer.CreateNoWindow = $true
            $killProcess = [Diagnostics.Process]::Start($killer)
            [void]$killProcess.WaitForExit(5000)
            $killProcess.Dispose()
            throw 'Git đã chờ quá lâu. Kiểm tra mạng hoặc cửa sổ đăng nhập GitHub rồi chạy lại.'
        }
        if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) {
            throw 'Git đã kết thúc nhưng tiến trình con vẫn giữ đầu ra. Kiểm tra Git hook hoặc công cụ ký commit rồi thử lại.'
        }
        $output = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        $result = [pscustomobject]@{ ExitCode=$process.ExitCode; Output=$output; Error=$errorText }
        if (-not $AllowFailure -and $result.ExitCode -ne 0) {
            throw ('Git thất bại: ' + ($output + "`n" + $errorText).Trim())
        }
        return $result
    } finally { $process.Dispose() }
}

function ConvertTo-GitHubRepository {
    param([AllowEmptyString()][string]$Text)
    $value = $Text.Trim()
    $match = [regex]::Match($value, '^(?:https://github\.com/|git@github\.com:)([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))/([A-Za-z0-9_.-]+)/?$', 'IgnoreCase')
    if (-not $match.Success) { throw 'Link repo chưa đúng. Dán link dạng https://github.com/ten-tai-khoan/ten-repo (không phải link file hoặc nhánh).' }
    $owner = $match.Groups[1].Value
    $repo = $match.Groups[2].Value -replace '(?i)\.git$', ''
    if (-not $repo -or $repo -eq '.' -or $repo -eq '..') { throw 'Tên repo GitHub chưa hợp lệ.' }
    [pscustomobject]@{ Url="https://github.com/$owner/$repo.git"; WebUrl="https://github.com/$owner/$repo"; Slug="$owner/$repo" }
}

function Test-SameRemote {
    param([string]$First, [string]$Second)
    try { return (ConvertTo-GitHubRepository $First).Url -eq (ConvertTo-GitHubRepository $Second).Url }
    catch { return $First.TrimEnd('/','\') -eq $Second.TrimEnd('/','\') }
}

function Assert-RemoteRouting {
    param([string]$Folder, [string]$RemoteUrl, [switch]$AllowLocalRemote)
    # Refuse any rewrite matching this URL rather than trying to reproduce Git's
    # longest-prefix rules. config queries also work before a folder has a repo.
    $rules = Invoke-GitCommand $Folder @('config','--null','--get-regexp','^url\..*\.(insteadof|pushinsteadof)$') -AllowFailure
    if ($rules.ExitCode -gt 1) { throw 'Không đọc được cấu hình định tuyến Git.' }
    foreach ($record in ($rules.Output -split "`0")) {
        if (-not $record) { continue }
        $separator=$record.IndexOf("`n")
        if ($separator -lt 0) { throw 'Không đọc được quy tắc định tuyến Git.' }
        $prefix=$record.Substring($separator+1)
        if ($RemoteUrl.StartsWith($prefix,[StringComparison]::Ordinal)) {
            throw 'Cấu hình Git đang định tuyến fetch/push sang đích khác URL đã nhập. Kiểm tra url.*.insteadOf và url.*.pushInsteadOf trước khi chạy.'
        }
    }
}

function Get-RepositoryState {
    param([string]$Folder)
    if (-not $Folder -or -not (Test-Path -LiteralPath $Folder -PathType Container)) { throw 'Chọn một thư mục code đang tồn tại trên máy.' }
    $path = (Get-Item -LiteralPath $Folder).FullName
    $probe = Invoke-GitCommand $path @('rev-parse','--show-toplevel') -AllowFailure
    $exists = $probe.ExitCode -eq 0
    if ($exists) {
        $root = [IO.Path]::GetFullPath($probe.Output.Trim())
        if ($root.TrimEnd('\','/') -ine $path.TrimEnd('\','/')) {
            throw "Hãy chọn thư mục gốc của repo: $root. Tool không tự thêm file từ repo cha."
        }
        $bare = Invoke-GitCommand $path @('rev-parse','--is-bare-repository')
        if ($bare.Output.Trim() -eq 'true') { throw 'Chọn thư mục mã nguồn, không chọn bare repository.' }
        $branchResult = Invoke-GitCommand $path @('symbolic-ref','--quiet','--short','HEAD') -AllowFailure
        if ($branchResult.ExitCode -ne 0) { throw 'Repo đang ở detached HEAD. Chuyển sang một nhánh trước khi chạy.' }
        $branch = $branchResult.Output.Trim()
        $originResult = Invoke-GitCommand $path @('remote','get-url','origin') -AllowFailure
        $origin = if ($originResult.ExitCode -eq 0) { $originResult.Output.Trim() } else { '' }
        $headResult = Invoke-GitCommand $path @('rev-parse','--verify','HEAD') -AllowFailure
        foreach ($marker in @('MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','rebase-merge','rebase-apply','sequencer','index.lock')) {
            $markerResult = Invoke-GitCommand $path @('rev-parse','--git-path',$marker)
            $markerPath = $markerResult.Output.Trim()
            if (-not [IO.Path]::IsPathRooted($markerPath)) { $markerPath = Join-Path $path $markerPath }
            if (Test-Path -LiteralPath $markerPath) { throw 'Repo đang có merge/rebase/cherry-pick hoặc Git khác đang chạy. Hoàn tất thao tác đó rồi thử lại.' }
        }
        $pushUrls = Invoke-GitCommand $path @('config','--get-all','remote.origin.pushurl') -AllowFailure
        if ($pushUrls.ExitCode -eq 0 -and $pushUrls.Output.Trim()) { throw 'origin có pushurl riêng. Xóa cấu hình remote.origin.pushurl trước để bảo đảm đúng đích push.' }
        $urls = Invoke-GitCommand $path @('config','--get-all','remote.origin.url') -AllowFailure
        if ($urls.ExitCode -eq 0 -and @($urls.Output.Trim() -split '\r?\n').Count -gt 1) { throw 'origin có nhiều đích repo. Giữ một URL duy nhất trước khi chạy.' }
        return [pscustomobject]@{ Folder=$path; Exists=$true; Branch=$branch; Origin=$origin; HasHead=($headResult.ExitCode -eq 0) }
    }
    # Do not initialize over a damaged repo, bare repo or an inaccessible parent Git directory.
    if (Test-Path -LiteralPath (Join-Path $path '.git')) { throw 'Không đọc được repo Git trong folder này. Kiểm tra quyền truy cập hoặc cấu hình safe.directory của Git.' }
    $bareProbe = Invoke-GitCommand $path @('rev-parse','--is-bare-repository') -AllowFailure
    if ($bareProbe.ExitCode -eq 0 -and $bareProbe.Output.Trim() -eq 'true') { throw 'Chọn thư mục mã nguồn, không chọn bare repository.' }
    $parent = [IO.Directory]::GetParent($path)
    while ($parent) {
        if (Test-Path -LiteralPath (Join-Path $parent.FullName '.git')) { throw 'Không đọc được repo gốc ở folder cha. Kiểm tra quyền truy cập Git trước khi chạy.' }
        $parent = $parent.Parent
    }
    [pscustomobject]@{ Folder=$path; Exists=$false; Branch='main'; Origin=''; HasHead=$false }
}

function Test-SecretPath {
    param([string]$Path)
    $name = ($Path -split '/')[-1]
    if ($name -match '^\.env(?:\.|$)' -and $name -notmatch '\.(example|sample|template)$') { return $true }
    return $name -match '(?i)\.(pem|key|p12|pfx)$|^id_(rsa|ed25519|ecdsa)(?:$|\.)|^credentials\.json$|^service[-_]account.*\.json$'
}

function Assert-NoTrackedSecrets {
    param([string]$Folder, [bool]$HasHead)
    $files = (Invoke-GitCommand $Folder @('ls-files','--cached','-z')).Output -split "`0"
    if ($HasHead) {
        $history = Invoke-GitCommand $Folder @('log','--format=','--name-only','-z','HEAD')
        $files += $history.Output -split "`0"
    }
    foreach ($file in $files) {
        $name = $file.Trim("`r","`n")
        if ($name -and (Test-SecretPath $name)) {
            throw "Phát hiện file có thể chứa bí mật đã được Git theo dõi hoặc có trong lịch sử: $name. Kiểm tra và xử lý file/lịch sử này trước; .gitignore không xóa dữ liệu đã commit."
        }
    }
}

function Add-StarterGitIgnore {
    param([string]$Folder)
    $path = Join-Path $Folder '.gitignore'
    $marker = '# GitHub Push Tool - local secrets and generated files'
    $content = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { '' }
    if ($content.Contains($marker)) { return }
    $rules = @'
# GitHub Push Tool - local secrets and generated files
.env
.env.*
!.env.example
!.env.sample
!.env.template
*.pem
*.key
*.p12
*.pfx
id_rsa
id_rsa.*
id_ed25519
id_ed25519.*
id_ecdsa
id_ecdsa.*
credentials.json
service-account*.json
service_account*.json
node_modules/
.venv/
venv/
__pycache__/
.vs/
.DS_Store
Thumbs.db
'@
    [IO.File]::WriteAllText($path, $content.TrimEnd("`r","`n") + "`r`n`r`n" + $rules.Replace("`r`n","`n").Replace("`n","`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))
}

function Invoke-ProjectPush {
    param(
        [string]$Folder,
        [string]$RemoteUrl,
        [string]$CommitMessage='',
        [string]$AuthorName='',
        [string]$AuthorEmail='',
        [switch]$ApproveRemoteChange,
        [switch]$AllowLocalRemote,
        [scriptblock]$OnProgress = { param($message) }
    )
    & $OnProgress 'Kiểm tra thư mục, nhánh và repo đích...'
    if (-not $AllowLocalRemote) { $RemoteUrl = (ConvertTo-GitHubRepository $RemoteUrl).Url }
    elseif (-not [IO.Path]::IsPathRooted($RemoteUrl) -or -not $RemoteUrl.EndsWith('.git')) { throw 'Local test remote must be an absolute .git path.' }
    $state = Get-RepositoryState $Folder
    $Folder = $state.Folder
    Assert-RemoteRouting $Folder $RemoteUrl -AllowLocalRemote:$AllowLocalRemote
    if ($state.Origin -and -not (Test-SameRemote $state.Origin $RemoteUrl) -and -not $ApproveRemoteChange) { throw 'origin hiện trỏ tới repo khác. Xác nhận đổi repo đích trước khi chạy.' }
    if ($state.Exists) { Assert-NoTrackedSecrets $Folder $state.HasHead }

    & $OnProgress 'Kiểm tra quyền truy cập GitHub (có thể mở trình duyệt đăng nhập)...'
    $remoteHeads = Invoke-GitCommand $Folder @('ls-remote','--heads','--',$RemoteUrl,"refs/heads/$($state.Branch)")
    $hasRemoteBranch = -not [string]::IsNullOrWhiteSpace($remoteHeads.Output)
    if ($hasRemoteBranch) {
        if (-not $state.HasHead) { throw 'Nhánh đích trên GitHub đã có lịch sử. Hãy clone repo đó trước rồi chép code vào; tool không tự ghép hoặc ghi đè hai lịch sử.' }
        & $OnProgress 'Kiểm tra thay đổi mới trên nhánh GitHub...'
        [void](Invoke-GitCommand $Folder @('fetch','--no-tags','--no-recurse-submodules','--',$RemoteUrl,"refs/heads/$($state.Branch)"))
        $ancestor = Invoke-GitCommand $Folder @('merge-base','--is-ancestor','FETCH_HEAD','HEAD') -AllowFailure
        if ($ancestor.ExitCode -ne 0) { throw 'GitHub có commit mới hoặc lịch sử khác với code trên máy. Đồng bộ và xử lý xung đột trước rồi chạy lại; tool không tự ghi đè lịch sử.' }
    }
    if (-not $state.Exists) {
        & $OnProgress 'Khởi tạo Git trên nhánh main...'
        [void](Invoke-GitCommand $Folder @('init','--initial-branch=main'))
    }
    if ($AuthorName.Trim()) { [void](Invoke-GitCommand $Folder @('config','--local','user.name',$AuthorName.Trim())) }
    if ($AuthorEmail.Trim()) {
        if ($AuthorEmail.Trim() -notmatch '^[^\s@<>]+@[^\s@<>]+$') { throw 'Email tác giả chưa hợp lệ. Mở Tác giả commit để sửa.' }
        [void](Invoke-GitCommand $Folder @('config','--local','user.email',$AuthorEmail.Trim()))
    }
    $author = Invoke-GitCommand $Folder @('var','GIT_AUTHOR_IDENT') -AllowFailure
    $committer = Invoke-GitCommand $Folder @('var','GIT_COMMITTER_IDENT') -AllowFailure
    if ($author.ExitCode -ne 0 -or $committer.ExitCode -ne 0) { throw 'Git chưa có tên/email tác giả. Bấm Tác giả commit, nhập tên và email rồi chạy lại.' }
    if (-not $state.Origin) { [void](Invoke-GitCommand $Folder @('remote','add','origin',$RemoteUrl)) }
    elseif ($state.Origin -cne $RemoteUrl) { [void](Invoke-GitCommand $Folder @('remote','set-url','origin',$RemoteUrl)) }
    & $OnProgress 'Chuẩn bị file và .gitignore (bỏ qua .env, khóa riêng, node_modules)...'
    Add-StarterGitIgnore $Folder
    [void](Invoke-GitCommand $Folder @('add','--all','--','.'))
    Assert-NoTrackedSecrets $Folder $state.HasHead
    $diff = Invoke-GitCommand $Folder @('diff','--cached','--quiet','--exit-code') -AllowFailure
    $committed = $false
    if ($diff.ExitCode -eq 1) {
        if ([string]::IsNullOrWhiteSpace($CommitMessage)) { $CommitMessage = 'Cập nhật code - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
        & $OnProgress 'Đang tạo commit...'
        [void](Invoke-GitCommand $Folder @('commit','-m',$CommitMessage))
        $committed = $true
    } elseif ($diff.ExitCode -ne 0) { throw ('Không kiểm tra được thay đổi: ' + $diff.Output) }
    else { & $OnProgress 'Không có file mới cần commit. Kiểm tra và đẩy các commit hiện có...'
    }
    & $OnProgress "Đang push nhánh $($state.Branch) lên repo đích..."
    Assert-RemoteRouting $Folder $RemoteUrl -AllowLocalRemote:$AllowLocalRemote
    $effectivePushUrls=(Invoke-GitCommand $Folder @('remote','get-url','--push','--all','origin')).Output.Trim() -split '\r?\n'
    foreach ($effective in $effectivePushUrls) {
        if (-not (Test-SameRemote $effective $RemoteUrl) -or (-not $AllowLocalRemote -and $effective -notmatch '^https://github\.com/')) { throw 'Đích push origin đã thay đổi trong lúc chạy. Kiểm tra cấu hình Git rồi thử lại.' }
    }
    $push = Invoke-GitCommand $Folder @('-c','remote.origin.mirror=false','-c','push.followTags=false','push','--porcelain','--no-follow-tags','--recurse-submodules=no','--set-upstream','origin',"HEAD:refs/heads/$($state.Branch)")
    & $OnProgress 'THÀNH CÔNG — code đã được đẩy lên repo.'
    [pscustomobject]@{ Branch=$state.Branch; RemoteUrl=$RemoteUrl; Committed=$committed; Output=$push.Output; Folder=$Folder }
}
