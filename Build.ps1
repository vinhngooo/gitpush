$ErrorActionPreference='Stop'
$output=Join-Path $PSScriptRoot 'GitHub Push.exe'
if (Test-Path -LiteralPath $output) { throw 'GitHub Push.exe already exists. Move the old build before rebuilding.' }
Add-Type -Path (Join-Path $PSScriptRoot 'Launcher.cs') -ReferencedAssemblies 'System.Windows.Forms' -OutputAssembly $output -OutputType WindowsApplication
Write-Output "Built: $output"
