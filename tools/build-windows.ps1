# EpubReader Flutter Windows 构建脚本
#
# 原因：本仓库所在磁盘为 exFAT（不支持符号链接），Flutter Windows 插件构建
# 需要 .plugin_symlinks，因此把项目暂存到 NTFS 的 C 盘再构建，产物拷回 out/。
#
# 用法：powershell -ExecutionPolicy Bypass -File tools\build-windows.ps1

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repoRoot 'flutter'
$stage = 'C:\EpubReaderBuild\flutter'
$flutterBat = 'C:\src\flutter\bin\flutter.bat'
$outDir = Join-Path $repoRoot 'out'

if (-not (Test-Path $flutterBat)) {
    Write-Error "未找到 Flutter SDK：$flutterBat"
    exit 1
}

Write-Host "== 1/4 暂存项目到 C 盘 =="
$stageParent = Split-Path -Parent $stage
if (-not (Test-Path $stageParent)) { New-Item -ItemType Directory -Path $stageParent | Out-Null }
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
robocopy $src $stage /MIR /XD build .dart_tool ephemeral .plugin_symlinks /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { Write-Error "robocopy 失败（code $LASTEXITCODE）"; exit 1 }
$global:LASTEXITCODE = 0

Push-Location $stage
Write-Host "== 2/4 flutter pub get =="
& $flutterBat pub get
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }

Write-Host "== 2.5/4 预创建插件 junction（绕过 exFAT/无符号链接权限）=="
$pluginLinks = Join-Path $stage 'windows\flutter\ephemeral\.plugin_symlinks'
$depsFile = Join-Path $stage '.flutter-plugins-dependencies'
if (Test-Path $depsFile) {
    $deps = Get-Content $depsFile -Raw | ConvertFrom-Json
    if (-not (Test-Path $pluginLinks)) { New-Item -ItemType Directory -Path $pluginLinks -Force | Out-Null }
    foreach ($p in $deps.'plugins'.'windows') {
        $linkPath = Join-Path $pluginLinks $p.name
        if (-not (Test-Path $linkPath)) {
            New-Item -ItemType Junction -Path $linkPath -Target $p.path | Out-Null
        }
        Write-Host "  junction: $($p.name) -> $($p.path)"
    }
}

Write-Host "== 3/4 flutter build windows --release =="
& $flutterBat build windows --release
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location

Write-Host "== 4/4 拷回产物到 out\ =="
$releaseDir = Join-Path $stage 'build\windows\x64\runner\Release'
if (-not (Test-Path $releaseDir)) { Write-Error "未找到构建产物：$releaseDir"; exit 1 }

$bundleName = "EpubReader.v26.1.0-alpha-windows-x64"
$dest = Join-Path $outDir $bundleName
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item -Path (Join-Path $releaseDir '*') -Destination $dest -Recurse -Force

Write-Host ""
Write-Host "构建完成：$dest"
Get-ChildItem $dest | Format-Table Name, Length -AutoSize
