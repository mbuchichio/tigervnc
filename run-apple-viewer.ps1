# With Emulate macOS keys enabled (default): Win -> Option, Alt -> Command,
# Ctrl -> Control on both sides. The checkbox is in Input > Keyboard.
# Any arguments are forwarded to TigerVNC (host, existing options, etc.).
$ErrorActionPreference = 'Stop'
$viewerPath = Join-Path $PSScriptRoot 'dist/apple-viewer/vncviewer.exe'
if (!(Test-Path -LiteralPath $viewerPath -PathType Leaf)) {
  throw 'Viewer not built. Run .\build-apple-viewer.ps1 first.'
}
& $viewerPath @args
