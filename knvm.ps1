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
#   Glyph seti. Dosya saf ASCII kalsin diye Unicode karakterler [char] kodu
#   ile uretiliyor: PowerShell 5.1 BOM'suz bir .ps1 dosyasini sistem ANSI kod
#   sayfasiyla okur, literal Unicode karakterler bozulurdu.
#   KNVM_ASCII=1 ile duz ASCII sete zorlanabilir.
# ---------------------------------------------------------------------------
$script:KnvmGlyphs = $null
function Get-Glyphs {
    if ($script:KnvmGlyphs) { return $script:KnvmGlyphs }

    $unicode = $false
    if ($env:KNVM_ASCII -ne "1") {
        try {
            if (-not [Console]::IsOutputRedirected) {
                if ([Console]::OutputEncoding.CodePage -ne 65001) {
                    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
                }
                $unicode = ([Console]::OutputEncoding.CodePage -eq 65001)
            }
        } catch { $unicode = $false }
    }

    if ($unicode) {
        $script:KnvmGlyphs = @{
            Rule = [string][char]0x2500   # yatay cizgi
            Cur  = [string][char]0x203A   # secim oku
            Mark = [string][char]0x25CF   # dolu daire (aktif / yuklu)
            Up   = [string][char]0x2191
            Down = [string][char]0x2193
        }
    } else {
        $script:KnvmGlyphs = @{ Rule = "-"; Cur = ">"; Mark = "*"; Up = "^"; Down = "v" }
    }
    return $script:KnvmGlyphs
}

# ---------------------------------------------------------------------------
# Invoke-Menu  -  ok tuslariyla gezilen interaktif secim menusu
#   Items      : ana sutun (ornegin surum adi)
#   Details    : sagda soluk gosterilen ikincil sutun (ornegin yol) - opsiyonel
#   Marked     : $g.Mark ile isaretlenecek indeksler (aktif/yuklu) - opsiyonel
#   Title      : menu ustu baslik
#   MaxVisible : ayni anda gorunen satir sayisi
# Donus degeri : secilen indeks  ya da  -1 (Escape / iptal)
# ---------------------------------------------------------------------------
function Invoke-Menu {
    param(
        [string[]]$Items,
        [string[]]$Details   = @(),
        [int[]]$Marked       = @(),
        [string]$Title       = "",
        [int]$MaxVisible     = 12
    )

    if ($null -eq $Items -or $Items.Count -eq 0) { return -1 }

    $total = $Items.Count
    $g     = Get-Glyphs

    # Konsol etkilesimli degilse (cikti/girdi yonlendirilmis, ISE, pipe...) imlec
    # konumlandirma calismaz - duz numarali listeye dus.
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) {
        if ($Title) { Write-Host ""; Write-Host "  $Title" -ForegroundColor Cyan }
        for ($i = 0; $i -lt $total; $i++) {
            $m = if ($Marked -contains $i) { $g.Mark } else { " " }
            $d = if ($i -lt $Details.Count -and $Details[$i]) { "   " + $Details[$i] } else { "" }
            Write-Host ("  {0,3}) {1} {2}{3}" -f ($i + 1), $m, $Items[$i], $d)
        }
        Write-Host ""
        $answer = Read-Host "  Numara (bos birakirsaniz iptal)"
        $n = 0
        if ($answer -and [int]::TryParse($answer.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $total) {
            return $n - 1
        }
        return -1
    }

    $sel = 0
    $top = 0
    $vis = [Math]::Min($MaxVisible, $total)

    # Menu pencereye sigmali: baslik, cizgiler ve ipucu satiri icin yer birak.
    # Sigmazsa her cizimde konsol kayar ve hizalama tutmaz.
    $winH = 0
    try { $winH = [Console]::WindowHeight } catch { $winH = 0 }
    if ($winH -gt 8) { $vis = [Math]::Max(1, [Math]::Min($vis, $winH - 6)) }

    # Draw'in bastigi satir sayisi: satirlar + alt cizgi + ipucu
    $frameRows = $vis + 2

    $w = 79
    try { $w = [Math]::Max(40, [Console]::WindowWidth) - 1 } catch { }

    # Ad sutunu: en uzun ogeye gore, ama genisligin ucte birini asmasin
    $nameW = 0
    foreach ($it in $Items) { if ($it.Length -gt $nameW) { $nameW = $it.Length } }
    $nameW = [Math]::Min($nameW, [Math]::Max(8, [int]($w / 3)))

    $detW = $w - ($nameW + 8)
    if ($detW -lt 0) { $detW = 0 }

    if ($Title) {
        Write-Host ""
        Write-Host ("  " + $Title) -ForegroundColor Cyan
        Write-Host ("  " + ($g.Rule * ($w - 2))) -ForegroundColor DarkGray
    }

    $drawn = $false

    function Draw {
        # Onceki cizimin ilk satirina don. Mutlak bir baslangic satiri saklamak
        # yerine her seferinde GUNCEL CursorTop'tan geri sayiyoruz; boylece iki
        # cizim arasinda konsol kaydirma (scroll) yapmis olsa bile hizalama
        # bozulmaz. Eski kod basta olculen $startRow'u sabit tutuyordu: imlec
        # ekranin altindayken menu asagi kayiyor, onceki kopya ekranda kaliyor
        # (menu "coklaniyor") ve $startRow + $vis + 1 tampon yuksekligini asinca
        # SetCursorPosition ArgumentOutOfRangeException firlatiyordu.
        if ($drawn) {
            $row = [Math]::Max(0, [Console]::CursorTop - $frameRows)
            [Console]::SetCursorPosition(0, $row)
        }

        for ($i = $top; $i -lt ($top + $vis); $i++) {
            $cur  = if ($i -eq $sel)          { $g.Cur }  else { " " }
            $mark = if ($Marked -contains $i) { $g.Mark } else { " " }

            $name = $Items[$i]
            if ($name.Length -gt $nameW) { $name = $name.Substring(0, $nameW) }
            $name = $name.PadRight($nameW)

            $det = if ($i -lt $Details.Count -and $Details[$i]) { $Details[$i] } else { "" }
            if ($det.Length -gt $detW) {
                if ($detW -gt 8) {
                    # Ortadan kisalt - yolun hem koku hem yapragi gorunur kalsin
                    $keep = $detW - 3
                    $head = [int][Math]::Floor($keep / 3)
                    $det  = $det.Substring(0, $head) + "..." +
                            $det.Substring($det.Length - ($keep - $head))
                } else {
                    $det = $det.Substring(0, $detW)
                }
            }
            $det = $det.PadRight($detW)

            # Satir genisligi tam olarak $w: 2 + (1+1) + (1+1) + nameW + 2 + detW
            if ($i -eq $sel) {
                Write-Host "  $cur $mark $name  $det" -ForegroundColor Black -BackgroundColor Cyan -NoNewline
            } else {
                Write-Host "  $cur "    -NoNewline
                Write-Host "$mark "     -ForegroundColor Green    -NoNewline
                Write-Host $name        -ForegroundColor Gray     -NoNewline
                Write-Host "  $det"     -ForegroundColor DarkGray -NoNewline
            }
            [Console]::WriteLine()
        }

        Write-Host ("  " + ($g.Rule * ($w - 2))) -ForegroundColor DarkGray -NoNewline
        [Console]::WriteLine()

        $u   = if ($top -gt 0)               { $g.Up }   else { " " }
        $d   = if (($top + $vis) -lt $total) { $g.Down } else { " " }
        $pos = "$u $($sel+1)/$total $d"

        $pairs = @(
            @(($g.Up + $g.Down), "gezin"),
            @("PgUp/PgDn",       "sayfa"),
            @("Enter",           "sec"),
            @("Esc",             "iptal")
        )
        $plain = "  $pos   " + (($pairs | ForEach-Object { "$($_[0]) $($_[1])" }) -join "   ")

        if ($plain.Length -le $w) {
            Write-Host "  $pos   " -ForegroundColor White -NoNewline
            $used = 2 + $pos.Length + 3
            for ($p = 0; $p -lt $pairs.Count; $p++) {
                $sep = if ($p -lt $pairs.Count - 1) { "   " } else { "" }
                Write-Host $pairs[$p][0] -ForegroundColor Cyan -NoNewline
                Write-Host (" " + $pairs[$p][1] + $sep) -ForegroundColor DarkGray -NoNewline
                $used += $pairs[$p][0].Length + 1 + $pairs[$p][1].Length + $sep.Length
            }
            if ($used -lt $w) { Write-Host (" " * ($w - $used)) -NoNewline }
        } else {
            $short = "  $pos   Enter sec   Esc iptal"
            if ($short.Length -gt $w) { $short = $short.Substring(0, $w) }
            Write-Host $short.PadRight($w) -ForegroundColor DarkGray -NoNewline
        }
        [Console]::WriteLine()
    }

    try {
        try { [Console]::CursorVisible = $false } catch { }

        Draw
        $drawn = $true

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
                # Draw her zaman son satiri WriteLine ile bitirir; imlec zaten
                # menunun hemen altindadir, ayrica konumlandirmaya gerek yok.
                "Enter"  { return $sel }
                "Escape" { return -1 }
            }
            Draw
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
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

            # Tablo artik menunun kendisi: surum ana sutunda, LTS/tarih soluk
            # ikincil sutunda, yuklu olanlar isaretli.
            $menuItems = [System.Collections.Generic.List[string]]::new()
            $menuDets  = [System.Collections.Generic.List[string]]::new()
            $menuMarks = [System.Collections.Generic.List[int]]::new()

            $i = 0
            foreach ($v in $rows) {
                $ver      = $v.version
                $ltsName  = if ($v.lts -and $v.lts -isnot [bool]) { $v.lts } else { "-" }
                $date     = $v.date.Substring(0, 10)
                $verClean = $ver.TrimStart('v')

                if ($installed -contains $verClean -or $installed -contains $ver) {
                    $menuMarks.Add($i)
                }
                $menuItems.Add($ver)
                $menuDets.Add(("LTS {0,-14}  {1}" -f $ltsName, $date))
                $i++
            }

            $idx = Invoke-Menu -Items $menuItems.ToArray() `
                               -Details $menuDets.ToArray() `
                               -Marked $menuMarks.ToArray() `
                               -Title "Bir surum secin  -  isaretliler zaten yuklu" `
                               -MaxVisible 12
            if ($idx -lt 0) {
                Write-Host "  Iptal edildi." -ForegroundColor DarkGray
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
                Write-Host "  Aktif versiyon: " -ForegroundColor Green -NoNewline
                Write-Host $activeName -ForegroundColor White
                Write-Host ""
            } else {
                Write-Host ""
                & "$KnvmHome\knvm.ps1" install $chosenVer
            }
        } else {
            $cfg   = Get-Config
            $props = @($cfg.versions.PSObject.Properties)
            if ($props.Count -eq 0) {
                Write-Host ""
                Write-Host "  Kayitli versiyon yok. Once 'knvm add' veya 'knvm install' kullanin." -ForegroundColor DarkGray
                Write-Host ""
            } else {
                $g     = Get-Glyphs
                $nameW = 0
                foreach ($v in $props) { if ($v.Name.Length -gt $nameW) { $nameW = $v.Name.Length } }

                Write-Host ""
                foreach ($v in $props) {
                    $isCur = ($cfg.current -eq $v.Name)
                    $mark  = if ($isCur) { $g.Mark } else { " " }
                    Write-Host "  $mark " -ForegroundColor Green -NoNewline
                    Write-Host $v.Name.PadRight($nameW) -ForegroundColor $(if ($isCur) { "White" } else { "Gray" }) -NoNewline
                    Write-Host "   $($v.Value)" -ForegroundColor DarkGray
                }
                Write-Host ""
                Write-Host "  $($g.Mark) = aktif surum" -ForegroundColor DarkGray
                Write-Host ""
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
            Write-Host "  Aktif versiyon: " -ForegroundColor Green -NoNewline
            Write-Host $Arg1 -ForegroundColor White
        } else {
            $cfg   = Get-Config
            $props = @($cfg.versions.PSObject.Properties)
            if ($props.Count -eq 0) {
                Write-Host "  Kayitli versiyon yok. Once 'knvm add' veya 'knvm install' kullanin." -ForegroundColor Red
                exit 1
            }

            $names = @($props | ForEach-Object { $_.Name })
            $paths = @($props | ForEach-Object { [string]$_.Value })
            $marks = @()
            for ($i = 0; $i -lt $props.Count; $i++) {
                if ($cfg.current -eq $props[$i].Name) { $marks += $i }
            }

            $idx = Invoke-Menu -Items $names -Details $paths -Marked $marks `
                               -Title "Aktif etmek icin bir surum secin" -MaxVisible 10
            if ($idx -lt 0) {
                Write-Host "  Iptal edildi." -ForegroundColor DarkGray
                exit 0
            }

            $cfg.current = $props[$idx].Name
            Save-Config $cfg
            Write-Host ""
            Write-Host "  Aktif versiyon: " -ForegroundColor Green -NoNewline
            Write-Host $props[$idx].Name -ForegroundColor White
            Write-Host "  $($props[$idx].Value)" -ForegroundColor DarkGray
            Write-Host ""
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

