param([string]$Only = '')
$ErrorActionPreference = 'Stop'
$core = Join-Path (Split-Path $PSScriptRoot) 'Core.ps1'
if (-not (Test-Path -LiteralPath $core)) { throw 'Git engine is missing: cannot validate URLs or safely push a project yet.' }
. $core
$script:Passed = 0
$script:Failed = 0
$testRoot = Join-Path $env:TEMP ('GitHubPushTool-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }
function Expect-Throw([scriptblock]$action, [string]$pattern) {
    try { & $action } catch { if ($_.Exception.Message -match $pattern) { return }; throw }
    throw "Expected refusal matching: $pattern"
}
function Test([string]$name, [scriptblock]$action) {
    if ($Only -and $name -notmatch $Only) { return }
    try { & $action; $script:Passed++; Write-Host "PASS $name" -ForegroundColor Green }
    catch { $script:Failed++; Write-Host "FAIL $name : $($_.Exception.Message)" -ForegroundColor Red }
}
function Git([string]$folder, [string[]]$arguments) { (Invoke-GitCommand -Folder $folder -Arguments $arguments).Output.Trim() }
function New-Fixture {
    $id = [guid]::NewGuid().ToString('N')
    $folder = Join-Path $testRoot ("Dự án có dấu & space " + $id)
    $remote = Join-Path $testRoot ($id + '.git')
    [void](New-Item -ItemType Directory -Path $folder)
    [void](Git $testRoot @('init','--bare','--initial-branch=main',$remote))
    [pscustomobject]@{ Folder=$folder; Remote=$remote }
}
function Push-Fixture($fixture, [string]$message='Test update', [switch]$ApproveRemoteChange) {
    Invoke-ProjectPush -Folder $fixture.Folder -RemoteUrl $fixture.Remote -CommitMessage $message -AuthorName 'Tool Test' -AuthorEmail 'tool@example.invalid' -AllowLocalRemote -ApproveRemoteChange:$ApproveRemoteChange
}
Test 'URL validation canonicalizes HTTPS and SSH GitHub repos' {
    Assert ((ConvertTo-GitHubRepository ' https://github.com/my-org/my.repo.git ').Url -eq 'https://github.com/my-org/my.repo.git') 'HTTPS normalization failed'
    Assert ((ConvertTo-GitHubRepository 'git@github.com:my-org/my_repo.git').Url -eq 'https://github.com/my-org/my_repo.git') 'SSH normalization failed'
    foreach ($url in @('https://evil.test/a/b','https://github.com/a/b/tree/main','https://token@github.com/a/b','https://github.com/a/b?x=y','https://github.com/a/..','https://github.com/a/b;whoami')) {
        Expect-Throw { ConvertTo-GitHubRepository $url } 'GitHub|repo'
    }
}
Test 'First push initializes main and preserves Unicode paths and excludes secrets' {
    $f=New-Fixture
    [IO.File]::WriteAllText((Join-Path $f.Folder 'xin chào.txt'),'hello')
    [IO.File]::WriteAllText((Join-Path $f.Folder '.env'),'SECRET=do-not-push')
    [void](New-Item -ItemType Directory -Path (Join-Path $f.Folder 'node_modules'))
    [IO.File]::WriteAllText((Join-Path $f.Folder 'node_modules\test.js'),'dependency')
    $result=Push-Fixture $f 'message "quoted" & $(literal)'
    Assert ($result.Branch -eq 'main') 'New repo must use main'
    Assert ((Git $f.Folder @('log','-1','--format=%s')) -eq 'message "quoted" & $(literal)') 'Commit argument was altered'
    Assert ((Git $testRoot @('--git-dir',$f.Remote,'show','main:xin chào.txt')) -eq 'hello') 'Remote content missing'
    $tracked=Git $f.Folder @('ls-files')
    Assert ($tracked -notmatch '(?m)^\.env$|node_modules') 'Secret or dependencies were committed'
}
Test 'Update push includes deletions and unchanged run creates no extra commit' {
    $f=New-Fixture
    [IO.File]::WriteAllText((Join-Path $f.Folder 'old.txt'),'old')
    [void](Push-Fixture $f)
    Remove-Item -LiteralPath (Join-Path $f.Folder 'old.txt')
    [IO.File]::WriteAllText((Join-Path $f.Folder 'new.txt'),'new')
    [void](Push-Fixture $f)
    $head=Git $f.Folder @('rev-parse','HEAD')
    [void](Push-Fixture $f)
    Assert ((Git $f.Folder @('rev-parse','HEAD')) -eq $head) 'Unchanged run created a commit'
    Assert ((Git $testRoot @('--git-dir',$f.Remote,'ls-tree','--name-only','main')) -notmatch 'old.txt') 'Deleted file stayed on remote'
}
Test 'Nested folder selection cannot stage files from its parent' {
    $f=New-Fixture
    [void](Git $f.Folder @('init','--initial-branch=main'))
    $nested=Join-Path $f.Folder 'nested'
    [void](New-Item -ItemType Directory -Path $nested)
    [IO.File]::WriteAllText((Join-Path $f.Folder 'parent.txt'),'parent')
    Expect-Throw { Invoke-ProjectPush -Folder $nested -RemoteUrl $f.Remote -AllowLocalRemote } 'gốc|root'
    Assert ([string]::IsNullOrWhiteSpace((Git $f.Folder @('diff','--cached','--name-only')))) 'Parent index was modified'
}
Test 'Changing origin requires explicit approval and preserves it when refused' {
    $f=New-Fixture; $other=New-Fixture
    [IO.File]::WriteAllText((Join-Path $f.Folder 'file.txt'),'one')
    [void](Push-Fixture $f)
    $original=$f.Remote; $f.Remote=$other.Remote
    Expect-Throw { Push-Fixture $f } 'origin|repo'
    Assert ((Git $f.Folder @('remote','get-url','origin')) -eq $original) 'Refusal changed origin'
    [void](Push-Fixture $f -ApproveRemoteChange)
    Assert ((Git $f.Folder @('remote','get-url','origin')) -eq $other.Remote) 'Approved origin did not change'
}
Test 'Existing feature branch is preserved' {
    $f=New-Fixture
    [void](Git $f.Folder @('init','--initial-branch=feature/demo'))
    [IO.File]::WriteAllText((Join-Path $f.Folder 'file.txt'),'one')
    $result=Push-Fixture $f
    Assert ($result.Branch -eq 'feature/demo') 'Existing branch renamed'
}
Test 'Tracked secret refuses before staging other changes' {
    $f=New-Fixture
    [void](Git $f.Folder @('init','--initial-branch=main'))
    [IO.File]::WriteAllText((Join-Path $f.Folder '.env'),'secret')
    [void](Git $f.Folder @('add','.env'))
    [IO.File]::WriteAllText((Join-Path $f.Folder 'safe.txt'),'safe')
    Expect-Throw { Push-Fixture $f } 'bí mật|secret|\.env'
    Assert ((Git $f.Folder @('diff','--cached','--name-only')) -notmatch 'safe.txt') 'Refusal staged additional files'
}
Test 'Divergent remote refuses without force or creating a local commit' {
    $f=New-Fixture
    [IO.File]::WriteAllText((Join-Path $f.Folder 'file.txt'),'base')
    [void](Push-Fixture $f)
    $clone=Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    [void](Git $testRoot @('clone',$f.Remote,$clone))
    [void](Git $clone @('config','user.name','Other'))
    [void](Git $clone @('config','user.email','other@example.invalid'))
    [IO.File]::WriteAllText((Join-Path $clone 'remote.txt'),'remote')
    [void](Git $clone @('add','--all'))
    [void](Git $clone @('commit','-m','remote change'))
    [void](Git $clone @('push','origin','main'))
    $head=Git $f.Folder @('rev-parse','HEAD')
    [IO.File]::WriteAllText((Join-Path $f.Folder 'local.txt'),'local')
    Expect-Throw { Push-Fixture $f } 'mới|khác|lịch sử|history'
    Assert ((Git $f.Folder @('rev-parse','HEAD')) -eq $head) 'Refusal created a commit'
    Assert ([string]::IsNullOrWhiteSpace((Git $f.Folder @('diff','--cached','--name-only')))) 'Refusal staged changes'
}
Test 'Extra push URL refuses so no unintended destination receives code' {
    $f=New-Fixture; $other=New-Fixture
    [IO.File]::WriteAllText((Join-Path $f.Folder 'file.txt'),'base')
    [void](Push-Fixture $f)
    [void](Git $f.Folder @('config','remote.origin.pushurl',$other.Remote))
    Expect-Throw { Push-Fixture $f } 'pushurl|đích'
}
Test 'An inherited Git environment cannot redirect another project' {
    $f=New-Fixture; $other=New-Fixture
    [void](Git $other.Folder @('init','--initial-branch=main'))
    [IO.File]::WriteAllText((Join-Path $f.Folder 'intended.txt'),'intended')
    $oldDir=$env:GIT_DIR; $oldWork=$env:GIT_WORK_TREE
    try {
        $env:GIT_DIR=Join-Path $other.Folder '.git'
        $env:GIT_WORK_TREE=$other.Folder
        [void](Push-Fixture $f)
        Assert (Test-Path -LiteralPath (Join-Path $f.Folder '.git')) 'Selected project was not initialized'
    } finally { $env:GIT_DIR=$oldDir; $env:GIT_WORK_TREE=$oldWork }
    Assert ((Git $testRoot @('--git-dir',$f.Remote,'show','main:intended.txt')) -eq 'intended') 'Selected project was not pushed'
    Assert ([string]::IsNullOrWhiteSpace((Git $other.Folder @('ls-files')))) 'Other repository index changed'
}
Test 'Merge in progress refuses before creating commits' {
    $f=New-Fixture
    [IO.File]::WriteAllText((Join-Path $f.Folder 'file.txt'),'base')
    [void](Push-Fixture $f)
    [IO.File]::WriteAllText((Join-Path $f.Folder '.git\MERGE_HEAD'), (Git $f.Folder @('rev-parse','HEAD')))
    Expect-Throw { Push-Fixture $f } 'merge|rebase'
}
Test 'A secret removed from current files is still refused if present in history' {
    $f=New-Fixture
    [void](Git $f.Folder @('init','--initial-branch=main'))
    [void](Git $f.Folder @('config','user.name','Test'))
    [void](Git $f.Folder @('config','user.email','test@example.invalid'))
    [IO.File]::WriteAllText((Join-Path $f.Folder '.env'),'secret')
    [void](Git $f.Folder @('add','.env'))
    [void](Git $f.Folder @('commit','-m','bad old commit'))
    [void](Git $f.Folder @('rm','.env'))
    [void](Git $f.Folder @('commit','-m','delete secret'))
    Expect-Throw { Push-Fixture $f } 'bí mật|lịch sử'
    $refs=Invoke-GitCommand $testRoot @('--git-dir',$f.Remote,'show-ref') -AllowFailure
    Assert ($refs.ExitCode -eq 1 -and -not $refs.Output) 'Secret history reached the remote'
}
Test 'Git URL rewrites cannot redirect fetch or push to another repository' {
    foreach ($rewrite in @('insteadOf','pushInsteadOf')) {
        $f=New-Fixture; $other=New-Fixture
        [IO.File]::WriteAllText((Join-Path $f.Folder 'file.txt'),'base')
        [void](Push-Fixture $f)
        [void](Git $f.Folder @('config',("url.$($other.Remote).$rewrite"),$f.Remote))
        [IO.File]::WriteAllText((Join-Path $f.Folder 'new.txt'),'new')
        Expect-Throw { Push-Fixture $f } 'định tuyến|đích|rewrite'
        Assert ([string]::IsNullOrWhiteSpace((Git $f.Folder @('diff','--cached','--name-only')))) 'Rewrite refusal staged files'
        $refs=Invoke-GitCommand $testRoot @('--git-dir',$other.Remote,'show-ref') -AllowFailure
        Assert ($refs.ExitCode -eq 1) 'Unintended destination received code'
    }
}
Test 'Unreachable remote refuses before staging project files' {
    $f=New-Fixture
    $f.Remote=Join-Path $testRoot 'does-not-exist.git'
    [IO.File]::WriteAllText((Join-Path $f.Folder 'file.txt'),'base')
    Expect-Throw { Push-Fixture $f } 'Git|repo|truy cập'
    Assert (-not (Test-Path -LiteralPath (Join-Path $f.Folder '.git'))) 'Invalid remote initialized a repository'
}
Test 'Equivalent origin spelling is normalized to the chosen transport' {
    $f=New-Fixture
    [IO.File]::WriteAllText((Join-Path $f.Folder 'file.txt'),'base')
    [void](Push-Fixture $f)
    [void](Git $f.Folder @('remote','set-url','origin',($f.Remote+'/')))
    [void](Push-Fixture $f)
    Assert ((Git $f.Folder @('config','--get','remote.origin.url')) -eq $f.Remote) 'Origin was not normalized to the selected URL'
}
Test 'No-change run pushes existing local commits' {
    $f=New-Fixture
    [IO.File]::WriteAllText((Join-Path $f.Folder 'file.txt'),'base')
    [void](Push-Fixture $f)
    [void](Git $f.Folder @('commit','--allow-empty','-m','already committed locally'))
    $head=Git $f.Folder @('rev-parse','HEAD')
    $pushed=Push-Fixture $f
    Assert (-not $pushed.Committed) 'No-change run created a commit'
    Assert ((Git $testRoot @('--git-dir',$f.Remote,'rev-parse','main')) -eq $head) 'Pending local commit was not pushed'
}
Test 'Different-owner project works without trusting another folder or changing global config' {
    $f=New-Fixture
    [void](Git $f.Folder @('init','--initial-branch=main'))
    $nested=Join-Path $f.Folder 'nested'
    [void][IO.Directory]::CreateDirectory($nested)
    $before=(Invoke-GitCommand $testRoot @('config','--global','--get-all','safe.directory') -AllowFailure).Output
    $oldOwnerTest=$env:GIT_TEST_ASSUME_DIFFERENT_OWNER
    try {
        $env:GIT_TEST_ASSUME_DIFFERENT_OWNER='1'
        $state=Get-RepositoryState $f.Folder
        Assert ($state.Exists -and $state.Branch -eq 'main') 'Selected different-owner repo is still blocked'
        Expect-Throw { Get-RepositoryState $nested } 'gốc|root'
        $unselected=Invoke-GitCommand $testRoot @('-C',$f.Folder,'rev-parse','--show-toplevel') -AllowFailure
        Assert ($unselected.ExitCode -ne 0 -and $unselected.Error -match 'dubious ownership') 'Trust leaked to an unselected directory'
    } finally { $env:GIT_TEST_ASSUME_DIFFERENT_OWNER=$oldOwnerTest }
    $after=(Invoke-GitCommand $testRoot @('config','--global','--get-all','safe.directory') -AllowFailure).Output
    Assert ($before -ceq $after) 'Global safe.directory settings were changed'
}
Test 'Git output drain is bounded when a child retains stdout' {
    $f=New-Fixture
    $watch=[Diagnostics.Stopwatch]::StartNew()
    Expect-Throw { Invoke-GitCommand $f.Folder @('-c','alias.tool-output-test=!sleep 12 &','tool-output-test') -TimeoutSeconds 2 } 'tiến trình con|quá lâu'
    Assert ($watch.Elapsed.TotalSeconds -lt 10) 'Retained pipe blocked beyond the drain timeout'
}
Write-Host "RESULT: $script:Passed passed, $script:Failed failed. Fixtures: $testRoot"
if ($script:Failed -gt 0) { exit 1 }
