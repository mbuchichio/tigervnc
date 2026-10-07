# Package the portable viewer without compiler output or build subfolders.
[CmdletBinding()]
param(
  [string]$SourceDirectory = (Join-Path $PSScriptRoot 'dist/apple-viewer'),
  [string]$OutputPath = (Join-Path $PSScriptRoot 'dist/TigerVNC-1.16.2-apple-viewer-win64.zip'),
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$sourcePath = (Resolve-Path -LiteralPath $SourceDirectory -ErrorAction Stop).Path
$archivePath = [System.IO.Path]::GetFullPath($OutputPath)
if (!(Test-Path -LiteralPath $sourcePath -PathType Container)) {
  throw "Source is not a directory: $sourcePath"
}
if ([System.IO.Path]::GetExtension($archivePath) -ne '.zip') {
  throw 'OutputPath must end in .zip'
}
foreach ($name in @('vncviewer.exe', 'LICENCE.TXT', 'runtime-dlls.txt')) {
  if (!(Test-Path -LiteralPath (Join-Path $sourcePath $name) -PathType Leaf)) {
    throw "Missing $name. Run .\build-apple-viewer.ps1 first."
  }
}
foreach ($name in Get-Content -LiteralPath (Join-Path $sourcePath 'runtime-dlls.txt')) {
  if ($name -and !(Test-Path -LiteralPath (Join-Path $sourcePath $name) -PathType Leaf)) {
    throw "Missing runtime DLL: $name"
  }
}

# Prune build directories before descending into them, including nested ones.
$directories = [System.Collections.Generic.Queue[string]]::new()
$directories.Enqueue($sourcePath)
$files = @()
while ($directories.Count -gt 0) {
  foreach ($item in Get-ChildItem -LiteralPath $directories.Dequeue() -Force) {
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
    if ($item.PSIsContainer) {
      if ($item.Name -notin @('build', '.local-build', 'CMakeFiles')) {
        $directories.Enqueue($item.FullName)
      }
    } elseif ($item.FullName -ne $archivePath) {
      $files += $item
    }
  }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Path (Split-Path -Parent $archivePath) -Force | Out-Null
if (Test-Path -LiteralPath $archivePath) {
  if (!$Force) { throw "ZIP already exists: $archivePath. Use -Force to replace it." }
  Remove-Item -LiteralPath $archivePath -ErrorAction Stop
}
$zip = [System.IO.Compression.ZipFile]::Open(
  $archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($sourcePath.TrimEnd([char]92, [char]47).Length + 1)
    $entryName = 'apple-viewer/' + $relativePath.Replace([char]92, [char]47)
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $zip, $file.FullName, $entryName,
      [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
} finally {
  $zip.Dispose()
}
Write-Output "Packaged $($files.Count) files: $archivePath"
Write-Output 'Extract the ZIP and open apple-viewer\vncviewer.exe. Keep its DLLs beside it.'
