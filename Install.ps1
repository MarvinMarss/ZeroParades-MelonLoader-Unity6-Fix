# Experimental Unity 6000.3 / MelonLoader compatibility workaround.
# Tested on Zero Parades 6000.3.15f1 and MelonLoader 0.7.4-ci.2630.
# Builds from official Il2CppInterop sources; it does NOT download or distribute a prebuilt patched DLL.
# Read README.md before running. Use at your own risk.
param(
    [string]$GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Zero Parades',
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Note([string]$message) { Write-Host "[+] $message" -ForegroundColor Cyan }
function Ensure([bool]$condition, [string]$message) { if (-not $condition) { throw $message } }
try {
    Ensure (Test-Path -LiteralPath (Join-Path $GameDir 'ZeroParades.exe')) "ZeroParades.exe was not found at $GameDir . Specify -GameDir with the correct path."
    Ensure (Test-Path -LiteralPath (Join-Path $GameDir 'MelonLoader')) 'MelonLoader directory was not found.'
    Ensure (-not (Get-Process -Name ZeroParades -ErrorAction SilentlyContinue)) 'Close Zero Parades before continuing.'

    Ensure ($null -ne (Get-Command git -ErrorAction SilentlyContinue)) 'Git is missing. Install Git for Windows: winget install --id Git.Git -e'
    Ensure ($null -ne (Get-Command dotnet -ErrorAction SilentlyContinue)) '.NET 8 SDK is missing. Install: winget install --id Microsoft.DotNet.SDK.8 -e'
    $sdk8 = @(& dotnet --list-sdks | Where-Object { $_ -match '^8\.' })
    Ensure ($sdk8.Count -gt 0) '.NET SDK 8 is required (the .NET runtime alone is not sufficient). Install: winget install --id Microsoft.DotNet.SDK.8 -e'

    $prefer = Join-Path $GameDir 'MelonLoader\net6\Il2CppInterop.Runtime.dll'
    if (Test-Path -LiteralPath $prefer) {
        $target = $prefer
    } else {
        $candidates = @(Get-ChildItem -LiteralPath (Join-Path $GameDir 'MelonLoader') -Filter 'Il2CppInterop.Runtime.dll' -File -Recurse -ErrorAction Stop)
        Ensure ($candidates.Count -eq 1) "Expected one Il2CppInterop.Runtime.dll inside MelonLoader, found $($candidates.Count). No files were changed."
        $target = $candidates[0].FullName
    }
    Note "Target runtime: $target"

    $workRoot = Join-Path $PSScriptRoot 'work'
    # EXACT upstream commit used by MelonLoader Il2CppInterop 1.5.1-ci.845.
    # The v1.5.1 tag is NOT binary compatible with MelonLoader's injector transpiler.
    $repo = Join-Path $workRoot 'Il2CppInterop-ci845'
    $oldRepo = Join-Path $workRoot 'Il2CppInterop-v1.5.1'
    $expectedCommit = 'f03c8f4ae507d47ea814f3d11d1ec6b0391c1576'
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    if (Test-Path -LiteralPath (Join-Path $repo '.git')) {
        $currentCommit = (& git -C $repo rev-parse HEAD 2>$null).Trim()
        Ensure ($LASTEXITCODE -eq 0 -and $currentCommit -eq $expectedCommit) "Existing checkout has unexpected commit. Rename $repo and retry. No game files changed."
        Note 'Reusing exact pinned Il2CppInterop 1.5.1-ci.845 source.'
    } elseif (Test-Path -LiteralPath (Join-Path $oldRepo '.git')) {
        Note 'Fetching the exact ci.845 commit into previously downloaded Git repository...'
        & git -C $oldRepo fetch --quiet --depth 1 origin $expectedCommit
        Ensure ($LASTEXITCODE -eq 0) 'Git fetch failed. No game files changed.'
        & git -C $oldRepo worktree add --quiet --detach $repo $expectedCommit
        Ensure ($LASTEXITCODE -eq 0) 'Git worktree creation failed. No game files changed.'
    } else {
        Note 'Cloning upstream repository and checking out exact ci.845 commit...'
        & git clone --quiet --depth 1 --branch v1.5.1 'https://github.com/BepInEx/Il2CppInterop.git' $repo
        Ensure ($LASTEXITCODE -eq 0) 'Git clone failed. No game files changed.'
        & git -C $repo fetch --quiet --depth 1 origin $expectedCommit
        Ensure ($LASTEXITCODE -eq 0) 'Git fetch failed. No game files changed.'
        & git -C $repo checkout --quiet --detach $expectedCommit
        Ensure ($LASTEXITCODE -eq 0) 'Git checkout failed. No game files changed.'
    }
    $verifiedCommit = (& git -C $repo rev-parse HEAD).Trim()
    Ensure ($verifiedCommit -eq $expectedCommit) 'Wrong source commit: refusing to build or install.'
    $injectorPath = Join-Path $repo 'Il2CppInterop.Runtime\Injection\InjectorHelpers.cs'
    Ensure (Test-Path -LiteralPath $injectorPath) 'Expected InjectorHelpers.cs source file is missing.'
    $injectorText = [IO.File]::ReadAllText($injectorPath)
    Ensure ($injectorText.Contains('GenericMethodGetMethodHook_Unity6')) 'Critical MelonLoader field GenericMethodGetMethodHook_Unity6 missing from source. Refusing incompatible build.'
    Note 'Verified exact source commit and MelonLoader-required Unity6 hook field.'

    $file = Join-Path $repo 'Il2CppInterop.Runtime\Injection\Hooks\Class_GetFieldDefaultValue_Hook.cs'
    Ensure (Test-Path -LiteralPath $file) 'Expected source file was not found after cloning.'
    $source = [IO.File]::ReadAllText($file).Replace("`r`n", "`n")
    $signatureComment = '// Unity 6000.3.20 (x64), port of BepInEx/Il2CppInterop PR #291'
    if (-not $source.Contains($signatureComment)) {
        # Find the end of s_Signatures structurally; no newline/spacing-sensitive anchor.
        $arrayStart = $source.IndexOf('private static readonly MemoryUtils.SignatureDefinition[] s_Signatures', [StringComparison]::Ordinal)
        Ensure ($arrayStart -ge 0) 'Signature array declaration not found in v1.5.1 source. No game files were changed.'
        $methodStart = $source.IndexOf('private static nint FindClassGetFieldDefaultValueXref', $arrayStart, [StringComparison]::Ordinal)
        Ensure ($methodStart -gt $arrayStart) 'Signature lookup method not found. No game files were changed.'
        $arrayEnd = $source.LastIndexOf('};', $methodStart, [StringComparison]::Ordinal)
        Ensure ($arrayEnd -gt $arrayStart) 'Signature array terminator not found. No game files were changed.'
        $lastEntryBrace = $source.LastIndexOf('}', $arrayEnd - 1)
        Ensure ($lastEntryBrace -gt $arrayStart) 'Cannot find last signature entry. No game files were changed.'
        $between = $source.Substring($lastEntryBrace + 1, $arrayEnd - $lastEntryBrace - 1)
        Ensure ([string]::IsNullOrWhiteSpace($between)) 'Unexpected code before signature array terminator. No game files were changed.'

        $newSignature = @'
,
            // Unity 6000.3.20 (x64), port of BepInEx/Il2CppInterop PR #291
            new MemoryUtils.SignatureDefinition
            {
                pattern = "\x48\x89\x5C\x24\x08\x57\x48\x81\xEC\x00\x00\x00\x00\x48\x8B\x41\x10\x48\x8B\xD9\x48\x8B\xFA\x48\x2B\x98",
                mask = "xxxxxxxxx????xxxxxxxxxxxxx",
                xref = false
            }
'@
        $source = $source.Substring(0, $lastEntryBrace + 1) + $newSignature + $source.Substring($lastEntryBrace + 1)
    } else {
        Note 'Unity 6000.3 signature is already patched.'
    }

    $fallbackMarker = 'var getStaticFieldValueInternal = getStaticFieldValueTargets[^1];'
    if (-not $source.Contains('Field::GetDefaultFieldValue is inlined into Field::StaticGetValue')) {
        $markerPos = $source.IndexOf($fallbackMarker, [StringComparison]::Ordinal)
        Ensure ($markerPos -ge 0) 'Fallback insertion point not found. No game files were changed.'
        $markerNext = $source.IndexOf($fallbackMarker, $markerPos + $fallbackMarker.Length, [StringComparison]::Ordinal)
        Ensure ($markerNext -lt 0) 'Fallback insertion point is ambiguous. No game files were changed.'
        $guardPos = $source.LastIndexOf('if (getStaticFieldValueTargets.Count > 4)', $markerPos, [StringComparison]::Ordinal)
        Ensure ($guardPos -ge 0 -and ($markerPos - $guardPos) -lt 800) 'Expected fallback code did not match. No game files were changed.'
        $fallback = @'
// On Unity 6000.3+, the first target is Class::GetDefaultFieldValue,
                // while the second points into the blob reader.
                var unityVersion = Il2CppInteropRuntime.Instance.UnityVersion;
                if (getStaticFieldValueTargets.Count == 2 &&
                    (unityVersion.Major > 6000 || (unityVersion.Major == 6000 && unityVersion.Minor >= 3)))
                {
                    Logger.Instance.LogTrace("Field::GetDefaultFieldValue is inlined into Field::StaticGetValue");
                    return getStaticFieldValueTargets[0];
                }

'@
        $source = $source.Substring(0, $markerPos) + $fallback + "`n`n                " + $source.Substring($markerPos)
    } else {
        Note 'Unity 6000.3 fallback is already patched.'
    }

    # Check the two expected source edits before building. No DLL in the game was changed.
    Ensure ($source.Contains($signatureComment)) 'Signature verification failed.'
    Ensure ($source.Contains('Field::GetDefaultFieldValue is inlined into Field::StaticGetValue')) 'Fallback verification failed.'
    [IO.File]::WriteAllText($file, $source, ([System.Text.UTF8Encoding]::new($false)))
    Note 'Applied both parts of upstream PR #291 (source file only).'
    & git -C $repo diff -- 'Il2CppInterop.Runtime/Injection/Hooks/Class_GetFieldDefaultValue_Hook.cs' | Out-File -FilePath (Join-Path $PSScriptRoot 'source-patch.diff') -Encoding utf8
    Note 'Source diff saved to source-patch.diff.'

    # Zero Parades Unity 6000.3.15f1: the MetadataCache type-index hook points
    # at an unsafe target. Skipping this hook prevented repeatable native
    # access violations in the single tested installation. It may disable
    # class injection functionality for OTHER mods. Do not use in other games.
    $hookNeedle = 'GetTypeInfoFromTypeDefinitionIndexHook.ApplyHook();'
    $hookComment = '// ZERO_PARADES_DIAGNOSTIC: GetTypeInfoFromTypeDefinitionIndexHook.ApplyHook(); // skipped'
    $injectorText = [IO.File]::ReadAllText($injectorPath)
    $hookMatches = ([regex]::Matches($injectorText, [regex]::Escape($hookNeedle))).Count
    if ($injectorText.Contains($hookComment)) {
        Ensure ($hookMatches -eq 1) 'Ambiguous existing MetadataCache patch; refusing to build.'
        Note 'MetadataCache hook omission is already present.'
    } else {
        Ensure ($hookMatches -eq 1) "Expected one MetadataCache hook call, found $hookMatches. No game files changed."
        $injectorText = $injectorText.Replace($hookNeedle, $hookComment)
        [IO.File]::WriteAllText($injectorPath, $injectorText, ([System.Text.UTF8Encoding]::new($false)))
        Note 'Skipped MetadataCache type-index hook (experimental workaround).'
    }
    # Record both source edits so users can review exactly what was changed.
    & git -C $repo diff -- 'Il2CppInterop.Runtime/Injection/InjectorHelpers.cs' 'Il2CppInterop.Runtime/Injection/Hooks/Class_GetFieldDefaultValue_Hook.cs' |
        Out-File -FilePath (Join-Path $PSScriptRoot 'source-patch.diff') -Encoding utf8

    # v1.5.1's runtime project references an Il2Cppmscorlib reference DLL.
    $ref = Join-Path $repo 'Il2CppInterop.Runtime\Libs\Il2Cppmscorlib.dll'
    if (-not (Test-Path -LiteralPath $ref)) {
        $generatedRef = Join-Path $GameDir 'MelonLoader\Il2CppAssemblies\Il2Cppmscorlib.dll'
        Ensure (Test-Path -LiteralPath $generatedRef) "Reference Il2Cppmscorlib.dll not found at $generatedRef. No game files were changed."
        New-Item -ItemType Directory -Path (Split-Path $ref) -Force | Out-Null
        Copy-Item -LiteralPath $generatedRef -Destination $ref
        Note 'Copied the game-generated Il2Cppmscorlib reference for building.'
    }

    $proj = Join-Path $repo 'Il2CppInterop.Runtime\Il2CppInterop.Runtime.csproj'
    $buildLog = Join-Path $PSScriptRoot 'build-output.log'
    Note 'Building Il2CppInterop.Runtime (this may download NuGet dependencies)...'
    Push-Location $repo
    try {
        & dotnet build $proj --configuration Release --nologo -p:GeneratePackageOnBuild=false 2>&1 | Tee-Object -FilePath $buildLog
        $exitCode = $LASTEXITCODE
    } finally { Pop-Location }
    Ensure ($exitCode -eq 0) "Build failed. See $buildLog. No game files were changed."

    $outputs = @(Get-ChildItem -LiteralPath $repo -Filter 'Il2CppInterop.Runtime.dll' -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\\/]obj[\\/]' -and $_.FullName -match '[\\/]bin[\\/]' } |
        Sort-Object LastWriteTime -Descending)
    Ensure ($outputs.Count -gt 0) 'No compiled runtime DLL was found. No game files were changed.'
    $compiled = $outputs[0].FullName
    $newAssembly = [Reflection.AssemblyName]::GetAssemblyName($compiled)
    $oldAssembly = [Reflection.AssemblyName]::GetAssemblyName($target)
    Ensure ($newAssembly.Name -eq 'Il2CppInterop.Runtime') 'Built DLL has an unexpected assembly name.'
    Ensure ($newAssembly.Version.Major -eq $oldAssembly.Version.Major -and $newAssembly.Version.Minor -eq $oldAssembly.Version.Minor) "Incompatible major/minor assembly version: new $($newAssembly.Version), installed $($oldAssembly.Version). No game files were changed."

    $delivery = Join-Path $PSScriptRoot 'Il2CppInterop.Runtime.patched.dll'
    Copy-Item -LiteralPath $compiled -Destination $delivery -Force
    Note "Build succeeded. Patched DLL saved at: $delivery"
    Note 'Source compatibility check passed (GenericMethodGetMethodHook_Unity6).'
    if ($BuildOnly) {
        Note 'BuildOnly requested; no game files have been modified.'
        exit 0
    }

    # First-install safety: NEVER overwrite without a verified rollback backup.
    $backups = Join-Path $PSScriptRoot 'backups'
    $recordFile = Join-Path $backups 'install-record.json'
    Ensure (-not (Test-Path -LiteralPath $recordFile)) "An installation record already exists at $recordFile. Restore first or back up and inspect it; refusing to overwrite."
    New-Item -ItemType Directory -Path $backups -Force | Out-Null
    $backup = Join-Path $backups ("Il2CppInterop.Runtime.before-fix-{0}.dll" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Ensure (-not (Test-Path -LiteralPath $backup)) "Backup path already exists at $backup ."
    Copy-Item -LiteralPath $target -Destination $backup -ErrorAction Stop
    $oldHash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
    Ensure ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $oldHash) 'Original DLL backup could not be verified.'
    try {
        Copy-Item -LiteralPath $compiled -Destination $target -Force -ErrorAction Stop
        $patchedHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        Ensure ($patchedHash -eq (Get-FileHash -LiteralPath $compiled -Algorithm SHA256).Hash) 'Installed DLL hash mismatch.'
        @{ target = $target; backup = $backup; originalSHA256 = $oldHash;
            patchedSHA256 = $patchedHash; game = $GameDir;
            pinnedCommit = $expectedCommit; modification = 'PR291-backport + skip MetadataCache hook';
            installedUtc = [DateTime]::UtcNow.ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $recordFile -Encoding UTF8 -ErrorAction Stop
    } catch {
        Copy-Item -LiteralPath $backup -Destination $target -Force -ErrorAction Stop
        throw
    }
    Note "Experimental patched DLL installed. Original DLL backup: $backup"
    Write-Host ''
    Write-Host 'DONE. Test with EMPTY Mods first. If it runs, test one mod at a time.' -ForegroundColor Green
    Write-Host 'Restore original: powershell -NoProfile -ExecutionPolicy Bypass -File .\Restore.ps1'
    $disabled = Join-Path $GameDir 'version.dll.disabled'
    if (Test-Path -LiteralPath $disabled) {
        Write-Host '[!] version.dll.disabled exists. Re-enable MelonLoader manually if you disabled it earlier.' -ForegroundColor Yellow
    }
} catch {
    Write-Host ''
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Read Troubleshooting.md; no game DLL should be changed unless installation completed.'
    exit 1
}
