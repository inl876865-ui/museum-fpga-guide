param([string]$Output = (Join-Path $PSScriptRoot 'bin\FPGA_Media_Converter_Rebuilt.exe'))
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework x64 C# compiler was not found.' }
$sources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'source') -Filter '*.cs' | ForEach-Object FullName)
if (Test-Path -LiteralPath $Output) { throw 'Output already exists. Specify a new output file.' }
New-Item -ItemType Directory -Path (Split-Path $Output -Parent) -Force | Out-Null
& $compiler /nologo /target:winexe /platform:x64 /codepage:65001 /main:FpgaMedia.Program `
    /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Core.dll `
    /reference:System.Web.Extensions.dll "/out:$Output" $sources
if ($LASTEXITCODE) { throw 'Compilation failed.' }
[Console]::WriteLine("Built: " + $Output)
