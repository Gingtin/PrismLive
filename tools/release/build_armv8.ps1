# Builds the ARMv8 (arm64-v8a) version of PrismLive:
# 1. Compiles Rust purelive_core_rs for aarch64-linux-android (ARMv8 64-bit)
# 2. Synchronizes libpurelive_core_rs.so into jniLibs/arm64-v8a
# 3. Builds the Flutter APK targeting android-arm64 with --split-per-abi
# Usage:
#   pwsh tools/release/build_armv8.ps1 [-Mode Release|Debug] [-Out <dir>]

param(
    [ValidateSet("Release", "Debug")]
    [string]$Mode = "Release",
    [string]$Out = "$PSScriptRoot\..\..\build\release"
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."

Write-Host "=== Building PrismLive ARMv8 (arm64-v8a) [$Mode] ===" -ForegroundColor Cyan

# 1. Locate Android NDK
$ndkDir = $null
$sdkNdkBase = "$env:LOCALAPPDATA\Android\Sdk\ndk"
if (Test-Path $sdkNdkBase) {
    $ndkCandidate = Get-ChildItem -Path $sdkNdkBase -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($ndkCandidate) {
        $ndkDir = $ndkCandidate.FullName
    }
}
if (-not $ndkDir -and $env:ANDROID_NDK_HOME) {
    $ndkDir = $env:ANDROID_NDK_HOME
}

$rustCoreDir = "$root\rust\purelive_core_rs"
$jniLibsArm64 = "$root\apps\pure_live\android\app\src\main\jniLibs\arm64-v8a"
New-Item -ItemType Directory -Force -Path $jniLibsArm64 | Out-Null

if ($ndkDir -and (Test-Path "$ndkDir\toolchains\llvm\prebuilt\windows-x86_64\bin")) {
    Write-Host "[1/3] Compiling purelive_core_rs for aarch64-linux-android..." -ForegroundColor Green
    $llvmBin = "$ndkDir\toolchains\llvm\prebuilt\windows-x86_64\bin"
    $clangCmd = Get-ChildItem -Path $llvmBin -Filter "aarch64-linux-android*-clang.cmd" | Sort-Object Name | Select-Object -First 1
    $llvmAr = "$llvmBin\llvm-ar.exe"

    if ($clangCmd -and (Test-Path $llvmAr)) {
        Push-Location $rustCoreDir
        try {
            $prevPath = $env:PATH
            $prevCC = $env:CC_aarch64_linux_android
            $prevAR = $env:AR_aarch64_linux_android
            $prevLinker = $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER

            $env:PATH = "$llvmBin;$env:PATH"
            $env:CC_aarch64_linux_android = $clangCmd.FullName
            $env:AR_aarch64_linux_android = $llvmAr
            $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $clangCmd.FullName

            cargo build --release --target aarch64-linux-android
            if ($LASTEXITCODE -eq 0) {
                $builtSo = "$rustCoreDir\target\aarch64-linux-android\release\libpurelive_core_rs.so"
                if (Test-Path $builtSo) {
                    Copy-Item -Path $builtSo -Destination "$jniLibsArm64\libpurelive_core_rs.so" -Force
                    Write-Host "      Installed libpurelive_core_rs.so to $jniLibsArm64" -ForegroundColor Gray
                }
            } else {
                Write-Warning "Rust compilation exited with code $LASTEXITCODE; using existing so if available."
            }
        } finally {
            $env:PATH = $prevPath
            $env:CC_aarch64_linux_android = $prevCC
            $env:AR_aarch64_linux_android = $prevAR
            $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $prevLinker
            Pop-Location
        }
    }
} else {
    Write-Host "[1/3] Skipping Rust core rebuild (NDK not found), checking existing jniLibs..." -ForegroundColor Yellow
}

# 2. Build Flutter APK for ARMv8 (android-arm64)
Write-Host "[2/3] Building Flutter APK ($Mode, android-arm64)..." -ForegroundColor Green
Push-Location "$root\apps\pure_live"
try {
    # Avoid flaky local mirror if PURE_LIVE_USE_CN_MIRRORS caused handshake drops
    $prevMirror = $env:PURE_LIVE_USE_CN_MIRRORS
    $env:PURE_LIVE_USE_CN_MIRRORS = $null

    $buildFlag = if ($Mode -eq "Release") { "--release" } else { "--debug" }
    flutter build apk $buildFlag --target-platform android-arm64 --split-per-abi

    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk failed with exit code $LASTEXITCODE"
    }
} finally {
    $env:PURE_LIVE_USE_CN_MIRRORS = $prevMirror
    Pop-Location
}

# 3. Output verification and copy
Write-Host "[3/3] Verifying ARMv8 APK Artifacts..." -ForegroundColor Green
$apkSuffix = if ($Mode -eq "Release") { "release" } else { "debug" }
$apkPath = "$root\apps\pure_live\build\app\outputs\flutter-apk\app-arm64-v8a-$apkSuffix.apk"

if (-not (Test-Path $apkPath)) {
    throw "Expected APK not found: $apkPath"
}

$apkItem = Get-Item $apkPath
$sizeMb = [math]::Round($apkItem.Length / 1MB, 2)
Write-Host "Success! Generated ARMv8 APK: $apkPath" -ForegroundColor Cyan
Write-Host "Size: $sizeMb MB ($($apkItem.Length) bytes)" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$destPath = "$Out\PrismLive-arm64-v8a-$apkSuffix.apk"
Copy-Item -Path $apkPath -Destination $destPath -Force
Write-Host "Exported to: $destPath" -ForegroundColor Green
