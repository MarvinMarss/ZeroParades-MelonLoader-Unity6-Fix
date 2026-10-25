# Restore the original runtime from a backup created by Install.ps1.
# This does not uninstall MelonLoader or alter the game executable.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    $recordFile = Join-Path $PSScriptRoot 'backups\install-record.json'
    if (-not (Test-Path -LiteralPath $recordFile)) { throw 'No install manifest found. This script can only undo installations made by Install.ps1 in the same folder.' }
    if (Get-Process -Name ZeroParades -ErrorAction SilentlyContinue) { throw 'Close Zero Parades first.' }
    $record = Get-Content -LiteralPath $recordFile -Raw | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $record.backup)) { throw "Backup missing: $($record.backup)" }
    if (-not (Test-Path -LiteralPath $record.target)) { throw "Current DLL missing: $($record.target)" }
    $backupHash = (Get-FileHash -LiteralPath $record.backup -Algorithm SHA256).Hash
    if ($backupHash -ne $record.originalSHA256) { throw 'Original backup hash mismatch: refusing restore.' }
    $currentHash = (Get-FileHash -LiteralPath $record.target -Algorithm SHA256).Hash
    if ($currentHash -ne $record.patchedSHA256) { throw 'Current runtime has changed after installation. Refusing to overwrite it; restore manually from backup after investigating.' }
    Copy-Item -LiteralPath $record.backup -Destination $record.target -Force -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $record.target -Algorithm SHA256).Hash -ne $record.originalSHA256) {
        throw 'Restored runtime verification failed. Check permissions / filesystem.'
    }
    Remove-Item -LiteralPath $recordFile -ErrorAction Stop
    Write-Host '[+] Original MelonLoader runtime successfully restored.' -ForegroundColor Green
    Write-Host '[+] Backup file was retained for safety.'
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
