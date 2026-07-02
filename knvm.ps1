param(
    [Parameter(Position=0)][string]$Command = "",
    [Parameter(Position=1)][string]$Arg1    = "",
    [Parameter(Position=2)][string]$Arg2    = ""
)

$KnvmHome   = "$env:USERPROFILE\knvm"
$ConfigPath = "$KnvmHome\config.json"

function Get-Config {
    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return [PSCustomObject]@{ current = $null; versions = [PSCustomObject]@{} }
}

function Save-Config([PSCustomObject]$cfg) {
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
}

function Get-VersionPath([PSCustomObject]$cfg, [string]$name) {
    $prop = $cfg.versions.PSObject.Properties[$name]
    if ($prop) { return $prop.Value }
    return $null
}

# ---------------------------------------------------------------------------
# Invoke-Menu  -  ok tuslarÄ±yla gezilen interaktif secim menusu
#   Items      : goruntÃ¼lenecek string dizisi
#   Title      : menu ustu baslik (opsiyonel)
#   MaxVisible : ayni anda gorunen satir sayisi (varsayilan 12)
# Donus degeri : secilen indeks  ya da  -1 (Escape / iptal)
# ---------------------------------------------------------------------------
function Invoke-Menu {
    param(
        [string[]]$Items,
        [string]$Title   = "",
        [int]$MaxVisible = 12
    )

    if ($Items.Count -eq 0) { return -1 }

    $sel   = 0
    $top   = 0
    $total = $Items.Count
    $vis   = [Math]::Min($MaxVisible, $total)
    $w     = [Console]::WindowWidth

    [Console]::CursorVisible = $false

    if ($Title) { Write-Host $Title -ForegroundColor Cyan }

    $startRow = [Console]::CursorTop
    for ($i = 0; $i -le $vis; $i++) { [Console]::WriteLine() }

    function Draw {
        [Console]::SetCursorPosition(0, $startRow)
        for ($i = $top; $i -lt ($top + $vis); $i++) {
            $arrow = if ($i -eq $sel) { ">" } else { " " }
            $line  = ("  $arrow $($Items[$i])").PadRight($w - 1)
            if ($i -eq $sel) {
                Write-Host $line -ForegroundColor Black -BackgroundColor Cyan -NoNewline
            } else {
                Write-Host $line -ForegroundColor Gray -NoNewline
            }
            [Console]::WriteLine()
        }
        $upInd   = if ($top -gt 0)               { "(^)" } else { "   " }
        $downInd = if (($top + $vis) -lt $total) { "(v)" } else { "   " }
        $hint = "  $upInd $($sel+1)/$total $downInd  Yukari/Asagi=gezin  PgUp/PgDn  Enter=sec  Esc=iptal"
        Write-Host $hint.PadRight($w - 1) -ForegroundColor DarkGray -NoNewline
        [Console]::WriteLine()
    }

    try {
        Draw
        while ($true) {
            $k = [Console]::ReadKey($true)
            switch ($k.Key) {
                "UpArrow" {
                    if ($sel -gt 0) {
                        $sel--
                        if ($sel -lt $top) { $top = $sel }
                    }
                }
                "DownArrow" {
                    if ($sel -lt $total - 1) {
                        $sel++
                        if ($sel -ge $top + $vis) { $top = $sel - $vis + 1 }
                    }
                }
                "PageUp" {
                    $sel = [Math]::Max(0, $sel - $vis)
                    $top = [Math]::Max(0, $top - $vis)
                }
                "PageDown" {
                    $sel = [Math]::Min($total - 1, $sel + $vis)
                    if ($sel -ge $top + $vis) { $top = $sel - $vis + 1 }
                }
                "Home" { $sel = 0; $top = 0 }
                "End"  { $sel = $total - 1; $top = [Math]::Max(0, $total - $vis) }
                "Enter" {
                    [Console]::SetCursorPosition(0, $startRow + $vis + 1)
                    [Console]::CursorVisible = $true
                    return $sel
                }
                "Escape" {
                    [Console]::SetCursorPosition(0, $startRow + $vis + 1)
                    [Console]::CursorVisible = $true
                    return -1
                }
            }
            Draw
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

switch ($Command.ToLower()) {

    "add" {
        if (-not $Arg1 -or -not $Arg2) {
            Write-Host "Kullanim: knvm add <ad> <yol>" -ForegroundColor Red
            exit 1
        }
        $name     = $Arg1
        $nodePath = $Arg2.TrimEnd("\").TrimEnd("/")

        if (-not (Test-Path (Join-Path $nodePath "node.exe"))) {
            Write-Host "Hata: node.exe bulunamadi: $nodePath" -ForegroundColor Red
            exit 1
        }

        $npmCli = Join-Path $nodePath "node_modules\npm\bin\npm-cli.js"
        if (-not (Test-Path $npmCli)) {
            Write-Host "Uyari: npm-cli.js bulunamadi - npm shim calismayadilir." -ForegroundColor Yellow
        }

        $cfg = Get-Config
        $cfg.versions | Add-Member -NotePropertyName $name -NotePropertyValue $nodePath -Force
        Save-Config $cfg
        Write-Host "Eklendi: $name  ->  $nodePath" -ForegroundColor Green
    }

    "list" {
        if ($Arg1.ToLower() -eq "available") {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Write-Host "nodejs.org surum listesi aliniyor..." -ForegroundColor Cyan
            try {
                $index = (Invoke-WebRequest -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing).Content |
                         ConvertFrom-Json
            } catch {
                Write-Host "Hata: nodejs.org erisilemedi - $($_.Exception.Message)" -ForegroundColor Red
                exit 1
            }

            $cfg       = Get-Config
            $installed = @($cfg.versions.PSObject.Properties.Name)

            # Her major surumdeki en yeni release
            $rows = $index |
                Group-Object { ($_.version -replace '^v(\d+)\..*', '$1') } |
                ForEach-Object {
                    $_.Group |
                    Sort-Object { [System.Version]($_.version.TrimStart('v')) } -Descending |
                    Select-Object -First 1
                } |
                Sort-Object { [int]($_.version -replace '^v(\d+)\..*', '$1') } -Descending

            # Tablo baslik
            $h = "{0,-12}  {1,-16}  {2,-12}  {3}" -f "Versiyon", "LTS", "Tarih", "Durum"
            $s = "{0,-12}  {1,-16}  {2,-12}  {3}" -f "--------", "---", "----------", "------"
            Write-Host ""
            Write-Host $h -ForegroundColor White
            Write-Host $s -ForegroundColor DarkGray

            $menuItems = [System.Collections.Generic.List[string]]::new()
            foreach ($v in $rows) {
                $ver      = $v.version
                $ltsName  = if ($v.lts -and $v.lts -isnot [bool]) { $v.lts } else { "-" }
                $date     = $v.date.Substring(0, 10)
                $verClean = $ver.TrimStart('v')
                $isInst   = $installed -contains $verClean -or $installed -contains $ver
                $status   = if ($isInst) { "[yuklu]" } else { "" }

                $row   = "{0,-12}  {1,-16}  {2,-12}  {3}" -f $ver, $ltsName, $date, $status
                $color = if ($isInst) { "Green" } elseif ($ltsName -ne "-") { "Yellow" } else { "Gray" }
                Write-Host $row -ForegroundColor $color
                $menuItems.Add(("{0,-12}  {1,-10}  {2}" -f $ver, $ltsName, $status))
            }

            Write-Host ""
            Write-Host "  Sari=LTS  |  Yesil=Yuklu" -ForegroundColor DarkGray
            Write-Host ""

            $idx = Invoke-Menu -Items $menuItems.ToArray() -Title "Bir surum secin (yukle / aktif et):" -MaxVisible 12
            if ($idx -lt 0) {
                Write-Host "Iptal edildi." -ForegroundColor DarkGray
                exit 0
            }

            $chosen    = $rows[$idx]
            $chosenVer = $chosen.version.TrimStart('v')
            $isInst    = $installed -contains $chosenVer -or $installed -contains $chosen.version

            if ($isInst) {
                $activeName  = if ($installed -contains $chosenVer) { $chosenVer } else { $chosen.version }
                $cfg.current = $activeName
                Save-Config $cfg
                Write-Host ""
                Write-Host "Aktif versiyon: $activeName" -ForegroundColor Green
            } else {
                Write-Host ""
                & "$KnvmHome\knvm.ps1" install $chosenVer
            }
        } else {
            $cfg   = Get-Config
            $props = @($cfg.versions.PSObject.Properties)
            if ($props.Count -eq 0) {
                Write-Host "Kayitli versiyon yok."
            } else {
                foreach ($v in $props) {
                    $mark = if ($cfg.current -eq $v.Name) { "*" } else { " " }
                    Write-Host "  $mark $($v.Name)  =>  $($v.Value)"
                }
            }
        }
    }

    "use" {
        if ($Arg1) {
            $cfg = Get-Config
            if ($null -eq (Get-VersionPath $cfg $Arg1)) {
                Write-Host "Hata: $Arg1 kayitli degil. Once knvm add kullanin." -ForegroundColor Red
                exit 1
            }
            $cfg.current = $Arg1
            Save-Config $cfg
            Write-Host "Aktif versiyon: $Arg1" -ForegroundColor Green
        } else {
            $cfg   = Get-Config
            $props = @($cfg.versions.PSObject.Properties)
            if ($props.Count -eq 0) {
                Write-Host "Kayitli versiyon yok. Once 'knvm add' veya 'knvm install' kullanin." -ForegroundColor Red
                exit 1
            }
            $menuItems = $props | ForEach-Object {
                $mark = if ($cfg.current -eq $_.Name) { "*" } else { " " }
                "{0} {1,-15}  {2}" -f $mark, $_.Name, $_.Value
            }
            $idx = Invoke-Menu -Items $menuItems -Title "Aktif etmek icin bir surum secin:" -MaxVisible 10
            if ($idx -lt 0) {
                Write-Host "Iptal edildi." -ForegroundColor DarkGray
                exit 0
            }
            $cfg.current = $props[$idx].Name
            Save-Config $cfg
            Write-Host "Aktif versiyon: $($props[$idx].Name)" -ForegroundColor Green
        }
    }

    "current" {
        $cfg = Get-Config
        if (-not $cfg.current) {
            Write-Host "Aktif versiyon yok."
        } else {
            $p = Get-VersionPath $cfg $cfg.current
            Write-Host "$($cfg.current)  =>  $p"
        }
    }

    "remove" {
        if (-not $Arg1) {
            Write-Host "Kullanim: knvm remove <ad>" -ForegroundColor Red
            exit 1
        }
        $cfg = Get-Config
        if ($null -eq (Get-VersionPath $cfg $Arg1)) {
            Write-Host "Hata: $Arg1 kayitli degil." -ForegroundColor Red
            exit 1
        }
        $cfg.versions.PSObject.Properties.Remove($Arg1)
        if ($cfg.current -eq $Arg1) { $cfg.current = $null }
        Save-Config $cfg
        Write-Host "Silindi: $Arg1" -ForegroundColor Green
    }

    "resolve" {
        $cfg = Get-Config
        if (-not $cfg.current) {
            Write-Host "Hata: Aktif versiyon yok. knvm use calistirin." -ForegroundColor Red
            exit 1
        }
        $vPath = Get-VersionPath $cfg $cfg.current
        if (-not $vPath) {
            Write-Host "Hata: Aktif versiyon icin yol bulunamadi." -ForegroundColor Red
            exit 1
        }
        switch ($Arg1.ToLower()) {
            "node"    { Write-Output (Join-Path $vPath "node.exe") }
            "nodedir" { Write-Output $vPath }
            default   {
                Write-Host "Kullanim: knvm resolve node|nodedir" -ForegroundColor Red
                exit 1
            }
        }
    }

    "install" {
        if (-not $Arg1) {
            Write-Host "Kullanim: knvm install <versiyon|lts|latest>" -ForegroundColor Red
            exit 1
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $vInput  = $Arg1.ToLower().TrimStart("v")
        $version = $null

        if ($vInput -eq "lts" -or $vInput -eq "latest") {
            Write-Host "nodejs.org surum listesi aliniyor..." -ForegroundColor Cyan
            try {
                $index = (Invoke-WebRequest -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing).Content |
                         ConvertFrom-Json
            } catch {
                Write-Host "Hata: nodejs.org erisilemedi - $($_.Exception.Message)" -ForegroundColor Red
                exit 1
            }
            if ($vInput -eq "lts") {
                $entry    = $index | Where-Object { $_.lts -and $_.lts -ne $false } | Select-Object -First 1
                $codename = $entry.lts
                Write-Host "  LTS surumu: v$($entry.version.TrimStart('v')) ($codename)" -ForegroundColor Green
            } else {
                $entry = $index[0]
                Write-Host "  Son surum: v$($entry.version.TrimStart('v'))" -ForegroundColor Green
            }
            $version = $entry.version.TrimStart("v")
        } else {
            $version = $vInput
        }

        $VersionsDir = Join-Path $KnvmHome "versions"
        $TargetDir   = Join-Path $VersionsDir "v$version"

        if (Test-Path (Join-Path $TargetDir "node.exe")) {
            Write-Host "v$version zaten mevcut: $TargetDir" -ForegroundColor Yellow
            Write-Host "Aktif etmek icin: knvm use v$version" -ForegroundColor Cyan
            exit 0
        }

        $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
            "ARM64" { "arm64" }
            "x86"   { "x86"   }
            default { "x64"   }
        }

        $zipName   = "node-v$version-win-$arch.zip"
        $url       = "https://nodejs.org/dist/v$version/$zipName"
        $tmpZip    = Join-Path $env:TEMP $zipName
        $tmpExtDir = Join-Path $env:TEMP "knvm_extract_$version"

        Write-Host "  Indiriliyor : $url" -ForegroundColor Cyan
        try {
            $wc = [System.Net.WebClient]::new()
            $wc.DownloadFile($url, $tmpZip)
            $sizeMB = [math]::Round((Get-Item $tmpZip).Length / 1MB, 1)
            Write-Host "  Tamamlandi  : $sizeMB MB indirildi" -ForegroundColor Green
        } catch {
            Write-Host "Hata: Indirme basarisiz - $($_.Exception.Message)" -ForegroundColor Red
            Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
            exit 1
        }

        Write-Host "  Aciliyor..." -ForegroundColor Cyan
        if (Test-Path $tmpExtDir) { Remove-Item $tmpExtDir -Recurse -Force }
        try {
            Expand-Archive -Path $tmpZip -DestinationPath $tmpExtDir -Force
            $innerDir = (Get-ChildItem $tmpExtDir -Directory | Select-Object -First 1).FullName
            New-Item -ItemType Directory -Path $VersionsDir -Force | Out-Null
            Move-Item $innerDir $TargetDir -Force
            Write-Host "  Kuruldu     : $TargetDir" -ForegroundColor Green
        } catch {
            Write-Host "Hata: Zip acma basarisiz - $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        } finally {
            Remove-Item $tmpZip    -Force -ErrorAction SilentlyContinue
            Remove-Item $tmpExtDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        $cfg = Get-Config
        $cfg.versions | Add-Member -NotePropertyName "v$version" -NotePropertyValue $TargetDir -Force
        Save-Config $cfg
        Write-Host "  Kaydedildi  : v$version -> $TargetDir" -ForegroundColor Green
        Write-Host ""
        Write-Host "Aktif etmek icin: knvm use v$version" -ForegroundColor Cyan
    }

    default {
        Write-Host "knvm -- Kisisel Node Version Manager" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Komutlar:"
        Write-Host "  knvm add <ad> <yol>           Versiyon ekler"
        Write-Host "  knvm install <surum|lts>      nodejs.org dan indirir ve kaydeder"
        Write-Host "  knvm list                     Kayitli versiyonlari listeler"
        Write-Host "  knvm list available           Remote surumler - interaktif yukle/aktif et"
        Write-Host "  knvm use                      Interaktif menu ile aktif versiyonu degistirir"
        Write-Host "  knvm use <ad>                 Aktif versiyonu direkt degistirir"
        Write-Host "  knvm current                  Aktif versiyonu gosterir"
        Write-Host "  knvm remove <ad>              Versiyonu siler"
        Write-Host "  knvm resolve node|nodedir     Aktif node yolunu dondurur"
    }
}

