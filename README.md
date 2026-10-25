# Zero Parades / Unity 6 — MelonLoader startup crash workaround

[Русская инструкция](GUIDE-RU.md) · [Troubleshooting](TROUBLESHOOTING.md) · [Technical findings](UPSTREAM-REPORT.md)

An **experimental, source-built compatibility workaround** for *ZERO PARADES: For Dead Spies* on Unity 6000.3.15f1 when MelonLoader loads successfully but the game crashes before reaching the menu — even with **zero mods**.

> **Status: confirmed on ONE Windows 11 x64 installation, 25 October 2026.** The game reached the main menu, exited normally and the third-party **Force Crits Any Time** mod worked. Not a general fix for every Unity 6 game or every mod. Upstream developers have not endorsed this workaround.

## Tested configuration

| Component | Observed working configuration |
| --- | --- |
| Game | Zero Parades / Steam, Unity `6000.3.15f1` |
| OS | Windows 11 x64 |
| Loader | MelonLoader `0.7.4-ci.2630` |
| Il2CppInterop baseline | `1.5.1-ci.845`, exact source commit [`f03c8f4`](https://github.com/BepInEx/Il2CppInterop/commit/f03c8f4ae507d47ea814f3d11d1ec6b0391c1576) |
| Mod tested | [Force Crits Any Time](https://www.nexusmods.com/zeroparadesfordeadspies/mods/14) (`ZeroParadesDoubleSix.Melon.dll`) |

### Symptoms

- MelonLoader generates IL2CPP assemblies and reports `0 Mods loaded`, but Zero Parades still crashes before the main menu.
- Windows Event Viewer: `0xc0000005` access violation in `GameAssembly.dll`, **offset `0x66eb4b`** on the tested build. A different earlier build/configuration failed inside `coreclr.dll`.
- Debugger: `GameAssembly+0x66eb4b`, invalid pointer read. A `Class::Init signatures have been exhausted` warning also appeared, but is **not proven to be the root cause**.

## What this workaround changes

`Install.ps1`:

1. Clones the official [BepInEx/Il2CppInterop](https://github.com/BepInEx/Il2CppInterop) source and checks out the **specific commit** used by this MelonLoader build (not the incompatible `v1.5.1` release tag).
2. Backports the relevant `Class_GetFieldDefaultValue_Hook` handling associated with [Il2CppInterop PR #291](https://github.com/BepInEx/Il2CppInterop/pull/291), using the tested source-edit strategy.
3. **Skips** the call to `GetTypeInfoFromTypeDefinitionIndexHook.ApplyHook()` in `InjectorHelpers.Setup()` — the isolated change that stopped the reproducible crash in this case.
4. Compiles `Il2CppInterop.Runtime.dll` using the .NET 8 SDK, backs up the original runtime DLL, and installs the newly compiled file.

**Important caveat:** step 3 disables a runtime hook that other mods may need (especially mods that inject new IL2CPP-managed types). This is a *compatibility workaround*, not a proven upstream-quality fix of the underlying address-resolution issue. If the game or another mod misbehaves, restore the original DLL.

Neither the game files `ZeroParades.exe` / `GameAssembly.dll` nor any original mod binaries are distributed or patched here. The project **does not include a compiled DLL**, a game executable, or private crash dumps.

## Install (Windows PowerShell)

**Prerequisites:** a working game and MelonLoader installation, [Git for Windows](https://git-scm.com/downloads/win), and [.NET SDK 8](https://dotnet.microsoft.com/en-us/download/dotnet/8.0) (SDK, not just runtime). You also need MelonLoader's generated `MelonLoader/Il2CppAssemblies/Il2Cppmscorlib.dll` from a previous startup. Close the game and back up your saves.

If needed, install the prerequisites using `winget`:

```powershell
winget install --id Git.Git -e
winget install --id Microsoft.DotNet.SDK.8 -e
```

Open a **new** PowerShell in the extracted repository folder and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

If Steam is installed elsewhere, specify the location of `ZeroParades.exe`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -GameDir 'D:\SteamLibrary\steamapps\common\Zero Parades'
```

To **build without installing** the patched DLL:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -BuildOnly
```

The script will save its build log and source diff locally, and save original DLL + installation manifest in the ignored `backups/` folder. Review `Install.ps1` before executing it. Only run code you trust; this script downloads source/dependencies and writes to the MelonLoader installation.

### Test

1. Make sure MelonLoader itself is enabled (if you previously renamed `version.dll` to `version.dll.disabled`, rename it back).
2. First launch Zero Parades with an **empty `Mods` folder**. Verify that the main menu loads and the game can close normally.
3. Back up your saves, then add only one compatible mod and retest. The mod above was successfully tested; other mods may not work.

## Restore the original runtime

Close the game and, from the same extracted project folder, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Restore.ps1
```

This restores the pre-patch MelonLoader runtime from its verified backup. It does not remove MelonLoader. Do not delete `backups/` until you have finished testing. For a clean vanilla run, you may temporarily disable MelonLoader by renaming its `version.dll` to `version.dll.disabled` where applicable.

## Limitations / safety

- **Only one tested game/loader combination.** Do not run this in other Unity games blindly.
- Source is built locally on your computer; **we have not run the consolidated `Install.ps1` end-to-end**. The underlying two source edits and compilation were previously tested separately, and the final DLL was tested in-game. Please report any issues with the consolidated installer.
- Other mods may require the disabled hook. Normal gameplay with all content has not been exhaustively tested.
- An exception inside `coreclr.dll` or an `EndOfStreamException` alone does not prove this is the same bug. Match the version and crash signature first.
- Do not upload **memory dumps, private user paths, Steam IDs, or save files** to public issues.
- Use at your own risk. This is a community workaround, **not** an official ZA/UM, MelonLoader, Il2CppInterop, or Nexus Mods release.

## References / credit

- [Il2CppInterop PR #291](https://github.com/BepInEx/Il2CppInterop/pull/291) — upstream proposed handling for newer Unity builds; the first part of the workaround draws from it.
- [Il2CppInterop issue #283](https://github.com/BepInEx/Il2CppInterop/issues/283) — related Unity 6000.3 / IL2CPP access violations; similarities are not proof of an identical cause.
- [MelonLoader issue #1159](https://github.com/LavaGang/MelonLoader/issues/1159) — reports of crashes with newer Unity 6000 builds.
- [BepInEx/Il2CppInterop](https://github.com/BepInEx/Il2CppInterop) and [LavaGang/MelonLoader](https://github.com/LavaGang/MelonLoader) are maintained by their respective contributors; this project is not affiliated.

Code in this repository (the original PowerShell scripts and docs) is released under [MIT](LICENSE). The third-party Il2CppInterop source fetched during the build retains **its own** upstream licensing terms.
