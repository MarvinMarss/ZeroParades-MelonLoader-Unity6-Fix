# Troubleshooting / Диагностика

This repository targets **one** MelonLoader/Unity 6000.3 crash signature, not every installation error. Check the **last** log lines and the Windows `Application Error` event **after** each test.

| Symptom | Likely stage | What to do |
| --- | --- | --- |
| `End of Central Directory record could not be found` while extracting `UnityDependencies_6000.3.15.zip` | Corrupt/incomplete archive | Close the game, delete the **specific corrupted ZIP** in `MelonLoader/Dependencies/Il2CppAssemblyGenerator`, let the loader redownload it, or download the corresponding archive from the **official** [MelonLoader.UnityDependencies releases](https://github.com/LavaGang/MelonLoader.UnityDependencies/releases). Not solved by our patch. |
| `Win32Exception (193)` when executing `Cpp2IL.exe` | Invalid/incompatible Cpp2IL executable | Check Windows Security history and the executable type; redownload from the [official Cpp2IL releases](https://github.com/SamboyCoding/Cpp2IL/releases). Do not indiscriminately disable antivirus. Not solved by our patch. |
| Crash with empty `Mods`, Unity `6000.3.15f1`, `GameAssembly.dll + 0x66eb4b`, `0xc0000005` | Likely this compatibility issue | Consider the workaround **only** if loader/version match the tested config. |
| `Could not find field GenericMethodGetMethodHook_Unity6` | Wrong Il2CppInterop source version / binary ABI | Don't use the plain `v1.5.1` tag. This project pins exact CI845 source commit `f03c8f4`. |
| `Class::Init signatures have been exhausted, using a substitute!` | A hook resolver used a fallback | Warning alone is **not proof** of a crash. Compare actual exception and stack. |
| `Game Version: UNKNOWN` | Loader couldn't read version metadata | Not independently evidence of the crash. |
| Source checkout missing after interrupted download | Failed Git operation | Remove **only** this project's `work/Il2CppInterop-ci845` folder (not the game's MelonLoader folder), then rerun installation. |
| Git or SDK command not found | Prerequisite missing or old PowerShell session | Install Git/.NET SDK 8 and open a **new** PowerShell window. |
| `Il2Cppmscorlib.dll` missing | IL2CPP assembly generation has not finished | Let MelonLoader generate interop assemblies first. A generated reference DLL is needed to build. |
| Game runs after workaround but another mod fails | Disabled MetadataCache hook may be required by that mod | Restore the original DLL with `Restore.ps1`. Don't describe this as a universal solution. |

## Where to get logs

Look for `Latest.log` in `MelonLoader/Logs` or `MelonLoader` depending on your installation. If the process terminates without a useful log error, use **Event Viewer → Windows Logs → Application → Application Error (Event 1000)**. For serious debugging a minidump plus `WinDbg` can show the faulting address and stack, but **do not upload full dumps publicly**.

Useful sanitized bug report fields: game build/Unity version, MelonLoader version, Il2CppInterop commit/version, whether `Mods` was empty, exception code, faulting module + relative offset, and the last 20–30 log lines with personal paths removed.

## How to disable the loader without losing the game

On installations using `version.dll` injection, close the game and rename the loader's `version.dll` to `version.dll.disabled`. That was sufficient to restore a vanilla launch in the tested installation. To test mods again, rename it back. **Do not** rename the actual game's `UnityPlayer.dll` or `GameAssembly.dll`.

## Avoid unnecessary changes

- Do not copy arbitrary `GameAssembly.dll` files from other game versions.
- Do not distribute copyrighted game binaries or memory dumps.
- Do not reinstall Steam, Windows or .NET based solely on `0xc0000005`.
- The original runtime backup is in `backups/` and is intentionally excluded from Git.
