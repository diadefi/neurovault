param([ValidateSet('test','build','sim','serve')][string]$Action = 'test')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root
$localCompiler = Join-Path $root '.tools\solc-0.8.24.exe'
if (Test-Path -LiteralPath $localCompiler) { $env:FOUNDRY_SOLC = $localCompiler }
$forgeCommand = Get-Command forge -ErrorAction SilentlyContinue
$forge = if ($forgeCommand) { $forgeCommand.Source } else { Join-Path (Split-Path $root -Parent) 'pqc_eth44\ethereum\tools\foundry-1.4.2\forge.exe' }
switch ($Action) {
    'test' { & $forge test; if ($LASTEXITCODE) { exit $LASTEXITCODE }; npm.cmd test --prefix offchain; exit $LASTEXITCODE }
    'build' { & $forge build; if ($LASTEXITCODE) { exit $LASTEXITCODE }; python tools/export-artifacts.py; exit $LASTEXITCODE }
    'sim' {
        $localPython = Join-Path $root '.tools\python'
        if (Test-Path -LiteralPath $localPython) { $env:PYTHONPATH = $localPython }
        python sim/snn_sim.py; exit $LASTEXITCODE
    }
    'serve' { python -m http.server 8089 --bind 127.0.0.1 --directory frontend }
}
