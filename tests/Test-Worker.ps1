$ErrorActionPreference='Stop'
$toolRoot=Split-Path $PSScriptRoot
. (Join-Path $toolRoot 'Core.ps1')
$job=Join-Path $env:TEMP ('GitHubPushTool-worker-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($job)
$request=@{ Action='Push'; Folder=$job; RemoteUrl='https://example.invalid/not-github/repo'; CommitMessage=''; AuthorName=''; AuthorEmail=''; ApproveRemoteChange=$false }
$path=Join-Path $job 'request.json'
[IO.File]::WriteAllText($path,($request | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$info.Arguments='-NoProfile -ExecutionPolicy Bypass -File '+(ConvertTo-NativeArgument (Join-Path $toolRoot 'Worker.ps1'))+' -RequestPath '+(ConvertTo-NativeArgument $path)
$info.UseShellExecute=$false; $info.CreateNoWindow=$true
$process=[Diagnostics.Process]::Start($info)
if (-not $process.WaitForExit(20000)) { $process.Kill(); throw 'Worker did not finish' }
if ($process.ExitCode -ne 1) { throw 'Worker should return failure for an invalid destination' }
$result=[IO.File]::ReadAllText((Join-Path $job 'result.json')) | ConvertFrom-Json
if ($result.Success -ne $false -or $result.Message -notmatch 'Link repo') { throw 'Worker did not return an actionable validation error' }
if (Test-Path -LiteralPath (Join-Path $job '.git')) { throw 'Invalid worker request initialized a repository' }
if (-not [IO.File]::ReadAllText((Join-Path $job 'progress.log')).Contains('DỪNG')) { throw 'Worker did not record failure in the progress log' }
$process.Dispose()
Write-Output 'PASS worker process: rejects invalid destination, writes progress and atomic result, preserves folder.'
