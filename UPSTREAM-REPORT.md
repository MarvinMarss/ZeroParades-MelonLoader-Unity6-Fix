# Technical report for upstream developers

This is an **observational case study**, not proof of a generic Il2CppInterop bug or a production-quality patch. Please do not open duplicate issues without checking existing discussions.

## Environment

- Game: Zero Parades (Steam, single-player), Unity `6000.3.15f1` / `GameAssembly.dll` build 7 October 2026.
- OS: Windows 11 x64.
- Loader: `MelonLoader 0.7.4-ci.2630 Open-Beta`.
- Bundled interop: `Il2CppInterop 1.5.1-ci.845+f03c8f4ae507d47ea814f3d11d1ec6b0391c1576`.
- Native IL2CPP metadata: version 39 (seen during Cpp2IL generation).
- No installed mods were required to reproduce the loader crash.

## Reproduction and observations

1. Without the loader injection (`version.dll` disabled), the game launches.
2. With unmodified MelonLoader, the game crashes while no mods are loaded. A Windows event reported `c0000005` in `coreclr.dll` at offset `0x15d34e` in the earlier state.
3. Backporting the proposed `Class_GetFieldDefaultValue_Hook` handling from [#291](https://github.com/BepInEx/Il2CppInterop/pull/291) into the **matching CI845 baseline** removed some crashes/misdetected targets, but the game still crashed: `GameAssembly.dll + 0x66eb4b`, exception `0xc0000005`, repeatable on multiple launches.
4. The `GameAssembly.dll + 0x66eb4b` minidump showed `mov rbx, [rsi]` reading an invalid address (`INVALID_POINTER_READ`) with the call stack passing through `UnityPlayer.dll`. The dump did **not** contain enough public symbols to identify the exact native method.
5. **Only after temporarily omitting** the call to `GetTypeInfoFromTypeDefinitionIndexHook.ApplyHook()` in `InjectorHelpers.Setup()` did the game load the main menu and log a normal `Received Quit Request! Shutting down` plus `Preferences Saved!`.
6. The third-party *Force Crits Any Time* mod was later loaded and functionally tested with that bypass.

This A/B outcome strongly implicates the `MetadataCache` type-index **hook installation or its resolved native target**, but it **does not** establish whether the actual defect is in the signature/XREF resolver, the native target selection, the hook ABI, or a downstream dependency. Bypassing the hook may break class injection and must not be merged upstream without a real root-cause fix and tests.

## Relevant log patterns

**Unsuccessful:**

```text
[WARNING] [Il2CppInterop] Class::Init signatures have been exhausted, using a substitute!
[DEBUG] Registered mono icall UnityEngine.Transform::SetAsLastSibling in il2cpp domain
# process later terminates, WER: GameAssembly.dll +0x66eb4b (0xc0000005)
```

**Successful with hook skipped:**

```text
0 Mods loaded.
Registered mono icall UnityEngine.Transform::SetAsLastSibling in il2cpp domain
[ML Core] Received Quit Request! Shutting down...
Preferences Saved!
```

## Suggested upstream investigation

- Examine the resolved target for `MetadataCache_GetTypeInfoFromTypeDefinitionIndex_Hook` on Unity 6000.3.15f1 and compare it to an actual function prologue and call references.
- Investigate native ABI/signature assumptions for metadata v39 and optimized Unity 6000.3 binaries.
- Add guarded signature validation and fail-safe hook skipping instead of patching an unverified address.
- Retain full compatibility with the exact interop version bundled in a loader; the public `v1.5.1` tag differed from CI845 and missed `GenericMethodGetMethodHook_Unity6`.

## Related work

- [Il2CppInterop issue #283](https://github.com/BepInEx/Il2CppInterop/issues/283)
- [Il2CppInterop PR #291](https://github.com/BepInEx/Il2CppInterop/pull/291)
- [MelonLoader issue #1159](https://github.com/LavaGang/MelonLoader/issues/1159)

Please reproduce with your own dump and symbols. This repo intentionally does not distribute user crash dumps, game assemblies or generated IL2CPP binaries.
