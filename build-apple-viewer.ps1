# Build the patched Windows viewer and publish its local runtime bundle.
# Requires CMake, Ninja, Git and the MSYS2 UCRT64 packages listed in the doc.
$ErrorActionPreference = 'Stop'
$msysPrefix = 'C:/msys64/ucrt64'
$sourceDirectory = $PSScriptRoot.Replace([char]92, [char]47)
$localDirectory = "$sourceDirectory/.local-build"
$fltkSource = "$localDirectory/fltk-src"
$fltkBuild = "$localDirectory/fltk-build"
$fltkInstall = "$localDirectory/fltk"
$viewerBuild = "$localDirectory/apple-viewer"
$outputDirectory = "$sourceDirectory/dist/apple-viewer"
$fltkCommit = 'a66273e72621887fcbd0ee5dca2dd133356d5d8a'

foreach ($command in @('cmake', 'ninja', 'git')) {
  Get-Command $command -ErrorAction Stop | Out-Null
}
foreach ($file in @('bin/gcc.exe', 'bin/g++.exe', 'bin/windres.exe',
                    'bin/objdump.exe', 'include/jpeglib.h',
                    'include/pixman-1/pixman.h', 'include/gnutls/gnutls.h',
                    'include/nettle/eax.h', 'include/zlib.h')) {
  if (!(Test-Path -LiteralPath "$msysPrefix/$file" -PathType Leaf)) {
    throw "Missing $msysPrefix/$file. See doc/windows-left-win-option-experiment.md for build dependencies."
  }
}

$savedPath = $env:PATH
try {
  $env:PATH = "$msysPrefix/bin;$savedPath"
  New-Item -ItemType Directory -Path $localDirectory -Force | Out-Null
  if (!(Test-Path -LiteralPath "$fltkSource/.git")) {
    & git clone --depth 1 --branch release-1.3.9 https://github.com/fltk/fltk.git $fltkSource
    if ($LASTEXITCODE -ne 0) { throw 'FLTK source download failed' }
  }
  $actualCommit = & git -C $fltkSource rev-parse HEAD
  if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $fltkCommit) {
    throw "Expected FLTK 1.3.9 commit $fltkCommit in $fltkSource"
  }

  & cmake -S $fltkSource -B $fltkBuild -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    "-DCMAKE_C_COMPILER=$msysPrefix/bin/gcc.exe" `
    "-DCMAKE_CXX_COMPILER=$msysPrefix/bin/g++.exe" `
    "-DCMAKE_INSTALL_PREFIX=$fltkInstall" `
    "-DCMAKE_PREFIX_PATH=$msysPrefix" `
    -DFLTK_BUILD_TEST=OFF -DFLTK_BUILD_EXAMPLES=OFF `
    -DOPTION_USE_GL=OFF -DOPTION_BUILD_SHARED_LIBS=OFF `
    -DOPTION_USE_SYSTEM_LIBJPEG=ON -DOPTION_USE_SYSTEM_ZLIB=ON `
    -DOPTION_USE_SYSTEM_LIBPNG=OFF
  if ($LASTEXITCODE -ne 0) { throw 'FLTK configuration failed' }
  & cmake --build $fltkBuild --target install --parallel 6
  if ($LASTEXITCODE -ne 0) { throw 'FLTK build failed' }

  $images = @(
    "$fltkInstall/lib/libfltk_images.a", "$fltkInstall/lib/libfltk_png.a",
    "$fltkInstall/lib/libfltk_z.a", "$msysPrefix/lib/libjpeg.dll.a"
  ) -join ';'
  & cmake -S $sourceDirectory -B $viewerBuild -G Ninja `
    -DCMAKE_BUILD_TYPE=RelWithDebInfo `
    "-DCMAKE_C_COMPILER=$msysPrefix/bin/gcc.exe" `
    "-DCMAKE_CXX_COMPILER=$msysPrefix/bin/g++.exe" `
    "-DCMAKE_RC_COMPILER=$msysPrefix/bin/windres.exe" `
    "-DCMAKE_PREFIX_PATH=$msysPrefix" `
    "-DFLTK_INCLUDE_DIR=$fltkInstall/include" `
    "-DFLTK_BASE_LIBRARY=$fltkInstall/lib/libfltk.a" `
    "-DFLTK_IMAGES_LIBRARY=$images" `
    -DBUILD_VIEWER=ON -DBUILD_WINVNC=OFF -DENABLE_NLS=OFF `
    -DENABLE_GNUTLS=ON -DENABLE_NETTLE=ON -DBUILD_STATIC_GCC=ON
  if ($LASTEXITCODE -ne 0) { throw 'Viewer configuration failed' }
  & cmake --build $viewerBuild --target vncviewer --parallel 6
  if ($LASTEXITCODE -ne 0) { throw 'Viewer build failed' }

  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
  $viewerPath = Join-Path $outputDirectory 'vncviewer.exe'
  Copy-Item -LiteralPath "$viewerBuild/vncviewer/vncviewer.exe" -Destination $viewerPath
  $runtimeFiles = @{}
  Get-ChildItem -LiteralPath "$msysPrefix/bin" -Filter '*.dll' | ForEach-Object {
    $runtimeFiles[$_.Name] = $_.FullName
  }
  $queue = [System.Collections.Generic.Queue[string]]::new()
  $queue.Enqueue($viewerPath)
  $copied = @{}
  while ($queue.Count -gt 0) {
    $binary = $queue.Dequeue()
    $imports = & "$msysPrefix/bin/objdump.exe" -p $binary
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $binary" }
    foreach ($line in $imports) {
      if ($line -match 'DLL Name:\s+(\S+)') {
        $dll = $Matches[1]
        if ($runtimeFiles.ContainsKey($dll) -and !$copied.ContainsKey($dll)) {
          $destination = Join-Path $outputDirectory $dll
          Copy-Item -LiteralPath $runtimeFiles[$dll] -Destination $destination
          $queue.Enqueue($destination)
          $copied[$dll] = $true
        }
      }
    }
  }
  $copied.Keys | Sort-Object | Set-Content -LiteralPath "$outputDirectory/runtime-dlls.txt"
  Copy-Item -LiteralPath "$sourceDirectory/LICENCE.TXT" -Destination $outputDirectory
  Write-Output "Built $viewerPath with $($copied.Count) runtime DLLs."
  Write-Output 'Launch with .\run-apple-viewer.ps1'
} finally {
  $env:PATH = $savedPath
}
