# Windows viewer mapping for Apple Screen Sharing

Base: official TigerVNC `v1.16.2`, commit
`b555312d70d7ff017f866649a7e7167af4eb8fca`.
Upstream release: <https://github.com/TigerVNC/tigervnc/releases/tag/v1.16.2>.

With **Input > Keyboard > Emulate macOS keys** enabled, the custom Windows
build sends both Win keys as Apple Option, both Alt keys as Apple Command,
and both Ctrl keys as Control. The checkbox is enabled by default in this
custom build to preserve the accepted mapping. Unchecking it restores the
upstream Windows behavior, including AltGr. OK applies the choice; Cancel
discards edits. It is saved through the viewer's existing settings machinery
(registry defaults or saved .tigervnc files) as `EmulateMacOSKeys`.

The user identified the remote Mac as Mac OS X 10.6 Snow Leopard. Remote
acceptance is limited to that server; newer macOS versions have not been
tested in this session.

An upstream interest inquiry was posted on issue #770:
<https://github.com/TigerVNC/tigervnc/issues/770#issuecomment-6046731728>.
It explicitly limits remote testing to Snow Leopard and proposes a disabled
default for a possible upstream contribution. This local build remains
enabled by default.
The mapping is compiled into C++; PowerShell builds or launches that binary.
It applies to every connection made by this custom Windows build.
There is no server detection or unrelated refactor. The Windows-only checkbox
was added at the user's subsequent request. Right Alt intentionally replaces
AltGr only while the option is enabled.

## Stable launch and rebuild

From the repository root:

```powershell
& .\run-apple-viewer.ps1
# Optionally pass the host and existing TigerVNC options:
& .\run-apple-viewer.ps1 'YOUR_MAC_HOST'
```

The launcher resolves `dist/apple-viewer/vncviewer.exe` relative to its own
location and forwards all arguments. It does not select an experimental
variant or fall back to another installed viewer.

After changing the C++ source, close this viewer, rebuild, and reconnect:

```powershell
& .\build-apple-viewer.ps1
& .\run-apple-viewer.ps1
```

An already running process retains its old code. Keep the generated runtime
DLLs beside the executable when copying the bundle.

To package the existing build as a portable release:

```powershell
& .\package-apple-viewer.ps1
```

Output: `dist/TigerVNC-1.16.2-apple-viewer-win64.zip`. Extract it and open
`apple-viewer/vncviewer.exe` directly. The ZIP includes the viewer, runtime
DLLs, runtime manifest and license. It does not include the repository or
compiler trees; any nested `build`, `.local-build` or `CMakeFiles` directories
inside the source bundle are also excluded. Packaging does not rebuild.
Use `-OutputPath` for a different ZIP filename. An existing ZIP is left intact;
use `-Force` to replace it when packaging again.

Packaging was verified with Windows PowerShell 5.1, including nested build
directory exclusion, retained non-build subfolders, output ZIP exclusion,
and replacement via `-Force`. The release contains 23 files; each archived
file's SHA256 matched its source runtime bundle file.

Requirements: Git, CMake, and Ninja on PATH, plus MSYS2 UCRT64 installed at
`C:/msys64/ucrt64`. In the MSYS2 UCRT64 shell, the dependency packages are:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-zlib mingw-w64-ucrt-x86_64-pixman mingw-w64-ucrt-x86_64-libjpeg-turbo mingw-w64-ucrt-x86_64-gnutls mingw-w64-ucrt-x86_64-nettle
```

The build script downloads and builds upstream FLTK 1.3.9, pinned to commit
`a66273e72621887fcbd0ee5dca2dd133356d5d8a`. TigerVNC 1.16.2 requires FLTK 1.3.
Dependencies and build trees live in ignored `.local-build/`.
The stable runtime bundle lives in ignored `dist/apple-viewer/`.

The viewer uses `RelWithDebInfo`, `BUILD_VIEWER=ON`, `BUILD_WINVNC=OFF`,
`ENABLE_GNUTLS=ON`, `ENABLE_NETTLE=ON`, `ENABLE_NLS=OFF`, and
`BUILD_STATIC_GCC=ON`. The script builds only the viewer target and recursively
copies its MSYS2 DLL imports. This build bundled 20 runtime DLLs; their names
are recorded in `dist/apple-viewer/runtime-dlls.txt`.

## Final mapping

| Physical key | Internal / QEMU code | Initial keysym | Final wire keysym | Tested Apple role |
| --- | --- | --- | --- | --- |
| Left Win | `0xdb` | `Super_L (0xffeb)` | `Meta_L (0xffe7)` | Option |
| Right Win | `0xdc` | `Super_R (0xffec)` | `Meta_R (0xffe8)` | Option |
| Left Alt | `0x38` | `Alt_L (0xffe9)` | unchanged | Command |
| Right Alt | `0xb8` | `Alt_R (0xffea)` | unchanged | Command |
| Left Ctrl | `0x1d` | `Control_L (0xffe3)` | unchanged | Control |
| Right Ctrl | `0x9d` | `Control_R (0xffe4)` | unchanged | Control |

With emulation enabled, Windows' fake Left Ctrl is still suppressed. Right Alt
stays `Alt_R` instead of being converted to `ISO_Level3_Shift`.
Ctrl is cleared only from the copied character-lookup state so Right Alt
shortcuts use ordinary symbols: German Right Alt + Q sends `q`, and
Spanish Right Alt + 2 sends `2`, rather than `@`.
Real Ctrl callbacks remain independent.

## Complete input-to-wire path

1. Windows delivers `WM_KEYDOWN` / `WM_SYSKEYDOWN` and corresponding key-up
   messages. `MSG.wParam` is the virtual key; `MSG.lParam` bits 16-23 are the
   scan code, bit 24 marks an extended key, and bit 30 is the previous-down
   state. Left Win normally arrives as `VK_LWIN=0x5b`, scan `0x5b`,
   extended=1 (physical set-1 sequence `E0 5B`).
2. When keyboard grab is active, `DesktopWindow::grabKeyboard()`
   (`vncviewer/DesktopWindow.cxx`) calls `win32_enable_lowlevel_keyboard()`
   (`vncviewer/win32.c`). Its `WH_KEYBOARD_LL` `keyboard_hook()` intercepts
   keys and posts equivalent messages with the scan/flag information.
   `message_hook()` maintains keyboard state and converts side-specific
   Shift/Ctrl/Alt virtual keys to generic versions. Win keys retain their
   side-specific virtual keys. Ungrabbed input uses normal Windows messages.
3. FLTK's Windows message loop (`src/Fl_win32.cxx` in FLTK 1.3) calls system
   handlers on the native MSG before ordinary FLTK translation.
   `Viewport` registers `Viewport::handleSystemEvent()` through
   `Fl::add_system_handler()` in `vncviewer/Viewport.cxx` and forwards focused
   viewer events to `KeyboardWin32::handleEvent()`.
4. `KeyboardWin32::handleEvent()` (`vncviewer/KeyboardWin32.cxx`) extracts the
   scan code, sets internal bit `0x80` for extended keys, and calls
   `fixSystemKeyCode()` and `translateSystemKeyCode()`. These normalize
   special keys such as Pause/Break, Print/SysRq and NumLock.
   Left Win remains `systemKeyCode=0xdb`, RFB/QEMU `keyCode=0xdb`.
   The former identifies the physical key for tracking; the latter is an
   optional protocol key code, not a keysym.
5. `translateVKey()` calls `lookupVKeyMap()` for layout-independent keys.
   The columns in `vkey_map` are virtual key, non-extended keysym, extended
   keysym. `{ VK_LWIN, NoSymbol, XK_Super_L }` produces `Super_L=0xffeb`.
   Other keys can use layout tables or `ToUnicode()` and `ucs2keysym()`.
   Shift-side correction and AltGr detection then run. On AltGr layouts,
   fake Left Ctrl is delayed/suppressed. With emulation enabled, Right Alt
   remains `Alt_R`; otherwise the original `ISO_Level3_Shift` conversion runs.
   Deferred real Left Ctrl is forwarded through `handleAltGrTimeout()` or
   `resolveAltGrDetection()`. Emulation ignores copied Ctrl state even for
   AltGr; disabled mode retains the original Ctrl+Alt character lookup.
6. The `KeyboardHandler` callback is `Viewport::handleKeyPress()`.
   `ShortcutHandler` may consume a local shortcut; otherwise
   `Viewport::sendKeyPress()` checks view-only mode and calls
   `CConnection::sendKeyPress()` through the viewer's `CConn` instance.
   Local shortcut processing still sees the original Super keysym.
7. `CConnection::sendKeyPress()` (`common/rfb/CConnection.cxx`) normalizes
   Hyper to Super and ISO Left Tab to Tab. The existing `__APPLE__` block
   applies to viewers built for macOS, not Windows viewers connected to a Mac.
   The new `_WIN32` block conditionally maps `Super_L/R -> Meta_L/R` when
   `EmulateMacOSKeys` is enabled, leaves `keyCode`
   intact, and stores the final keysym/code in `downKeys[systemKeyCode]`
   before calling `writer()->writeKeyEvent(keySym, keyCode, true)`.
8. On key-up, `KeyboardWin32` forwards `systemKeyCode` through
   `Viewport::handleKeyRelease()` / `sendKeyRelease()` to
   `CConnection::sendKeyRelease()`. The connection uses the stored keysym
   and code for `writeKeyEvent(..., false)`; it does not recompute the symbol.
   `releaseAllKeys()` uses the same path on focus loss or resets.
9. `CMsgWriter::writeKeyEvent()` (`common/rfb/CMsgWriter.cxx`) serializes
   standard RFB: type 4, one-byte down flag, two padding bytes, four-byte
   keysym in network byte order. The physical key code is omitted.
   If QEMU extended key events were negotiated and `keyCode != 0`, it writes
   type 255, subtype 0, two-byte down flag, four-byte keysym, four-byte key
   code. A server using physical QEMU codes may interpret the unchanged
   Win code instead of the remapped keysym.
   `endMsg()` flushes the output stream. `CConn::connect()`
   (`vncviewer/CConn.cxx`) supplies socket streams through `setStreams()`;
   negotiated security layers can wrap them.

Standard RFB bytes for Left Win:

```text
press:   04 01 00 00 00 00 ff e7
release: 04 00 00 00 00 00 ff e7
```

Right Win ends in `ff e8`; Right Alt ends in `ff ea`.

## Experiments and verification

A (`ISO_Level3_Shift=0xfe03`) did not produce Option in the user's test.
B (`Mode_switch=0xff7e`) also had no effect; captured diagnostics confirmed
standard RFB down/up serialization with that keysym. C (`Meta_L=0xffe7`)
succeeded after reconnecting with the correct binary. Its live log captured
Left Win input, internal `0xdb`, initial `Super_L`, and final `Meta_L`
on both press and release. The user confirmed "ahora si!".
The user subsequently requested the right-side extension D, then accepted
the result with "perfecto".

An independent firsthand Screen Sharing probe also reports Meta_L/Meta_R
as Option, Alt/Super as Command, and ISO_Level3_Shift/Mode_switch as ignored:
<https://zenn.dev/musicflow/articles/macos-screen-sharing-rfb-traps>.
This is experimental evidence, not an Apple protocol guarantee.

The temporary WINKEY logging at native input, translation, remapping, and
final serialization was removed from the stable build.
`CMsgWriter.cxx` is back to upstream with no changes.
Existing standard logging remains available through TigerVNC's Log option.

The stable build passed 27 local native keyboard checks. The probe links actual
KeyboardWin32, ShortcutHandler, CConnection and CMsgWriter build objects,
supplies Windows MSGs, and compares serialized bytes in MemOutStream.
It covers both sides, matched releases, repeat, release-all, local Super
shortcuts, unchanged QEMU physical codes, German fake Ctrl suppression,
real Ctrl, and German/Spanish Right Alt character lookup. The additional
disabled-mode checks verify original Super keysyms, both Ctrl keys,
ISO_Level3_Shift, German/Spanish AltGr characters, and matched key releases
when the option changes while a Win key is held.
It does not simulate the low-level hook, FLTK focus routing, transport,
or Apple interpretation; the user's live tests supply that evidence.

The bundled viewer also loaded and printed its 1.16.2 help/banner with PATH
restricted to Windows directories. Windows help waits indefinitely, so only
that test process was stopped after inspecting its output. Both root scripts
passed parsing in Windows PowerShell 5.1 and PowerShell 7.6.6.

A native OptionsDialog probe also passed five groups of checks: checkbox
placement and label bounds, default enabled state, Cancel/reload, OK applying
both states, and saved .tigervnc file restoration of the disabled state.
It uses the actual built dialog and parameters objects without opening a
remote session or writing registry defaults. Rerun with
`& .\_experiment\run-gui-option-probe.ps1`; results are in
`_experiment/gui-option-results.txt`. The GUI build log is
`_experiment/build-gui-mac-keys.log`.

Rerun locally with `& .\_experiment\run-keyboard-probe.ps1`.
Results: `_experiment/keyboard-probe-results.txt`.
Stable build log: `_experiment/build-canonical.log`.
Earlier binaries, diagnostics, and investigation notes are preserved under
`_experiment/ab/`, including `both-sides/`. These are local ignored artifacts.

For a repeat A/B experiment, change only the Left Win assignment in
`CConnection::sendKeyPress()` from `XK_Meta_L` to `XK_ISO_Level3_Shift`
or `XK_Mode_switch`, rebuild, and reconnect with emulation enabled;
the probe expectations must also be adjusted for the chosen experiment.

## Exact repository changes

- `common/rfb/CConnection.cxx`: Windows-only EmulateMacOSKeys parameter and
  conditional Super_L/R to Meta_L/R remap.
- `common/rfb/CConnection.h`: Windows-only parameter declaration.
- `vncviewer/KeyboardWin32.cxx`: Right Alt as Alt_R, copied character-lookup
  Ctrl state cleared when enabled, original AltGr behavior when disabled,
  existing fake Ctrl suppression retained.
- `vncviewer/OptionsDialog.cxx` and `vncviewer/OptionsDialog.h`: Windows-only
  Keyboard checkbox, tooltip, and option load/store.
- `vncviewer/parameters.cxx`: include the option in saved viewer settings.
- `build-apple-viewer.ps1`: repeatable build and runtime DLL bundling.
- `run-apple-viewer.ps1`: launcher for the stable output.
- `package-apple-viewer.ps1`: portable ZIP packaging without build directories.
- `.gitignore`: generated build trees and runtime bundle excluded.
- `doc/windows-left-win-option-experiment.md`: this path, usage and test record.
