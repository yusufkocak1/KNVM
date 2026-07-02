#Requires -Version 5.0
<#
.SYNOPSIS
    knvm kurulum scripti
.DESCRIPTION
    Dosyalari %USERPROFILE%\knvm altina kopyalar, User PATH'e shims klasorunu ekler
    ve PowerShell profiline PATH oncelik satirini yazar.
    Mevcut config.json korunur (versiyonlar silinmez).
    Guncelleme icin tekrar calistirilab.
#>

$ErrorActionPreference = "Stop"
$SourceDir = $PSScriptRoot
$KnvmHome  = "$env:USERPROFILE\knvm"
$ShimsDir  = "$KnvmHome\shims"

Write-Host "knvm kuruluyor..." -ForegroundColor Cyan
Write-Host "  Kaynak : $SourceDir"
Write-Host "  Hedef  : $KnvmHome"
Write-Host ""

# 1. Dizinleri olustur
New-Item -ItemType Directory -Path $KnvmHome -Force | Out-Null
New-Item -ItemType Directory -Path $ShimsDir -Force | Out-Null
Write-Host "  [+] Dizinler hazir" -ForegroundColor Green

# 2. knvm.ps1 kopyala
Copy-Item (Join-Path $SourceDir "knvm.ps1") (Join-Path $KnvmHome "knvm.ps1") -Force
Write-Host "  [+] knvm.ps1 kopyalandi" -ForegroundColor Green

# 3. Shim'leri kopyala
foreach ($f in Get-ChildItem -Path (Join-Path $SourceDir "shims") -Filter "*.cmd") {
    Copy-Item $f.FullName (Join-Path $ShimsDir $f.Name) -Force
}
Write-Host "  [+] Shim'ler kopyalandi (knvm.cmd, node.cmd, npm.cmd, npx.cmd)" -ForegroundColor Green

# 4. config.json olustur (yoksa — mevcut kayitlari korumak icin uzerine yazma)
$ConfigPath = Join-Path $KnvmHome "config.json"
if (-not (Test-Path $ConfigPath)) {
    [PSCustomObject]@{ current = $null; versions = [PSCustomObject]@{} } |
        ConvertTo-Json -Depth 10 |
        Set-Content $ConfigPath -Encoding UTF8
    Write-Host "  [+] config.json olusturuldu" -ForegroundColor Green
} else {
    Write-Host "  [=] config.json zaten mevcut, korundu" -ForegroundColor Yellow
}

# 5. User PATH'e shims klasorunu ekle
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if (-not $userPath) { $userPath = "" }

if ($userPath -notlike "*$ShimsDir*") {
    $newPath = ($userPath.TrimEnd(';') + ";$ShimsDir").TrimStart(';')
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "  [+] User PATH guncellendi: $ShimsDir eklendi" -ForegroundColor Green
} else {
    Write-Host "  [=] $ShimsDir zaten User PATH'de" -ForegroundColor Yellow
}

# 6. PowerShell profili — shims'i PATH'in basina tasi
#    Sistemde baska bir Node kurulumu Machine PATH'te kayitliysa (orn. eski nvm,
#    IntelliJ otomatik kurulumu) bu satir knvm shims'ini her zaman one alir.
$ProfilePath     = $PROFILE
$KnvmProfileLine = '$env:PATH = "$env:USERPROFILE\knvm\shims;" + ($env:PATH -replace [regex]::Escape("$env:USERPROFILE\knvm\shims;"), "")'
$ProfileDir      = Split-Path $ProfilePath

$profileRaw = if (Test-Path $ProfilePath) { Get-Content $ProfilePath -Raw } else { "" }

if ($profileRaw -notlike "*knvm\shims*") {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
    $newLines = [System.Collections.Generic.List[string]]::new()
    if ($profileRaw.Trim()) { $newLines.Add("") }   # bosluk satiri (varsa profil icin)
    $newLines.Add("# knvm shims - Machine PATH'deki node kurulumlarinin onune gec")
    $newLines.Add($KnvmProfileLine)
    [System.IO.File]::AppendAllLines($ProfilePath, $newLines, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [+] PowerShell profili guncellendi: $ProfilePath" -ForegroundColor Green
} else {
    Write-Host "  [=] PowerShell profili zaten knvm satirini iceriyor" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Kurulum tamamlandi!" -ForegroundColor Green
Write-Host ""
Write-Host "Siradaki adimlar:" -ForegroundColor Cyan
Write-Host "  1. Yeni bir terminal ac  (veya: . `$PROFILE)" -ForegroundColor White
Write-Host "  2. Node surumunu kaydet : knvm add <ad> <node-klasor-yolu>" -ForegroundColor White
Write-Host "  3. Aktif sur            : knvm use <ad>" -ForegroundColor White
Write-Host "  4. Dogrula              : node -v" -ForegroundColor White