# ustawmode - przelaczanie planu zasilania i profilu procesora w BIOS (ThinkPad)
#   ustawmode            -> lista do wyboru (strzalki + Enter, cyfra, Esc)
#   ustawmode gra        -> plan zasilania o tej nazwie (od razu)
#   ustawmode normalny   -> plan Zrownowazony (od razu)
#   ustawmode chlodny    -> BIOS: 6 rdzeni P, bez HT, bez rdzeni E + plan Zrownowazony (admin + restart)
#   ustawmode pelny      -> BIOS: wszystkie 16 rdzeni / 22 watki + plan Gra (admin + restart)
#   ustawmode diagnostyka -> jak teraz pracuje laptop (turbo, rdzenie, taktowanie, GPU, RAM, WSL...)
#   ustawmode logowanie   -> zapis temperatur do CSV na pulpicie co 5 s (ustawmode logowanie 10 = co 10 s), Ctrl+C = stop

$global:UstawmodeBios = [ordered]@{
    chlodny = @{
        Nazwa      = 'BIOS: chlodny (6 rdzeni, cicho) - wymaga restartu'
        Watki      = 6
        Plan       = '381b4222-f694-41f0-9685-ff5bb260df2e'   # Zrownowazony
        Ustawienia = [ordered]@{
            HyperThreadingTechnology = 'Disable'
            EfficientCores           = 'Disable'
            CPUPowerManagement       = 'Disable'
            EnergyEfficientTurbo     = 'Disable'
        }
    }
    pelny = @{
        Nazwa      = 'BIOS: pelna moc (16 rdzeni / 22 watki) - wymaga restartu'
        Watki      = 22
        Plan       = '14c57240-a9dd-4355-b6f0-f3e805e702e8'   # Gra
        Ustawienia = [ordered]@{
            HyperThreadingTechnology = 'Enable'
            EfficientCores           = 'Enable'
            CPUPowerManagement       = 'Enable'
            EnergyEfficientTurbo     = 'Enable'
        }
    }
}

function Get-PlanyZasilania {
    try {
        Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{
                    Typ     = 'plan'
                    Klucz   = $_.ElementName
                    Nazwa   = $_.ElementName
                    Guid    = ($_.InstanceID -replace '.*\{(.*)\}.*', '$1')
                    Aktywny = [bool]$_.IsActive
                }
            }
    } catch {
        powercfg /list | ForEach-Object {
            if ($_ -match 'GUID:\s*([0-9a-fA-F-]{36})\s+\((.+?)\)\s*(\*)?') {
                [pscustomobject]@{ Typ = 'plan'; Klucz = $matches[2]; Nazwa = $matches[2]; Guid = $matches[1]; Aktywny = [bool]$matches[3] }
            }
        }
    }
}

function Get-TrybyUstawmode {
    $watki = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    @(Get-PlanyZasilania)
    foreach ($k in $global:UstawmodeBios.Keys) {
        $p = $global:UstawmodeBios[$k]
        [pscustomobject]@{ Typ = 'bios'; Klucz = $k; Nazwa = $p.Nazwa; Guid = $null; Aktywny = ($watki -eq $p.Watki) }
    }
    [pscustomobject]@{ Typ = 'diag'; Klucz = 'diagnostyka'; Nazwa = 'Diagnostyka - jak teraz pracuje laptop'; Guid = $null; Aktywny = $false }
    [pscustomobject]@{ Typ = 'log'; Klucz = 'logowanie'; Nazwa = 'Logowanie temperatur na pulpit (co 5 s, Ctrl+C = stop)'; Guid = $null; Aktywny = $false }
}

function Get-TemperaturyUstawmode {
    Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue |
        ForEach-Object {
            [pscustomobject]@{
                Strefa    = ($_.Name -replace '.*\.', '')
                C         = [Math]::Round($_.HighPrecisionTemperature / 10 - 273.15, 1)
                Dlawienie = 100 - [int]$_.PercentPassiveLimit
            }
        }
}

function Start-LogowanieUstawmode {
    param([int]$Interwal = 5)
    if ($Interwal -lt 1) { $Interwal = 1 }
    $plik = Join-Path ([Environment]::GetFolderPath('Desktop')) ('temperatury_{0:yyyy-MM-dd_HH-mm-ss}.csv' -f (Get-Date))
    $nv = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    $inv = [Globalization.CultureInfo]::InvariantCulture
    Add-Type -AssemblyName System.Windows.Forms
    $zapytanie = { Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" }
    $null = & $zapytanie

    Write-Host "Logowanie co $Interwal s do: $plik" -ForegroundColor Cyan
    Write-Host 'Zatrzymanie: Ctrl+C' -ForegroundColor DarkGray
    Write-Host '(temperatura CPU = czujnik ACPI z Windows; jest nizsza i wolniejsza niz "Package" w HWiNFO)' -ForegroundColor DarkGray

    try {
        while ($true) {
            Start-Sleep -Seconds $Interwal
            $perf = & $zapytanie
            $mhz = if ($perf) { [Math]::Round($perf.ProcessorFrequency * $perf.PercentProcessorPerformance / 100) } else { $null }
            $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
            $plan = (Get-PlanyZasilania | Where-Object Aktywny | Select-Object -First 1).Nazwa

            $w = [ordered]@{
                Czas                = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                Zasilanie           = $(if ($ps.PowerLineStatus -eq 'Online') { 'zasilacz' } else { 'bateria' })
                Bateria_proc        = [int]($ps.BatteryLifePercent * 100)
                Plan                = $plan
                CPU_MHz             = $mhz
                CPU_obciazenie_proc = $(if ($perf) { [int]$perf.PercentProcessorTime } else { $null })
            }
            $tz = @(Get-TemperaturyUstawmode)
            foreach ($z in $tz) {
                $w["CPU_temp_$($z.Strefa)_C"] = $z.C
                $w["Dlawienie_$($z.Strefa)_proc"] = $z.Dlawienie
            }
            if ($nv) {
                $g = (nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu,clocks.gr --format=csv,noheader,nounits | Select-Object -First 1) -split ',\s*'
                $wat = 0.0
                $w['GPU_temp_C']          = $g[0]
                # RTX 4070 Laptop nie przekracza ~140 W; wieksze odczyty to bledne probki sterownika
                $w['GPU_W']               = $(if ([double]::TryParse($g[1], [Globalization.NumberStyles]::Float, $inv, [ref]$wat) -and $wat -lt 200) { $wat } else { $null })
                $w['GPU_obciazenie_proc'] = $g[2]
                $w['GPU_MHz']             = $g[3]
            }
            $os = Get-CimInstance Win32_OperatingSystem
            $w['RAM_uzyte_GB'] = [Math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)

            [pscustomobject]$w | Export-Csv -Path $plik -Append -NoTypeInformation -UseCulture -Encoding UTF8

            $tMax = ($tz | Measure-Object C -Maximum).Maximum
            $kolor = if ($tMax -ge 95) { 'Red' } elseif ($tMax -ge 85) { 'Yellow' } else { 'Green' }
            $dl = ($tz | Measure-Object Dlawienie -Maximum).Maximum
            $gpuTxt = if ($nv) { " | GPU $($w.GPU_temp_C) C $($w.GPU_obciazenie_proc)%" } else { '' }
            $dlTxt = if ($dl -gt 0) { " | DLAWIENIE $dl%" } else { '' }
            Write-Host ("{0}  CPU {1} C  {2} MHz  {3}%{4}{5}" -f $w.Czas.Substring(11), $tMax, $mhz, $w.CPU_obciazenie_proc, $gpuTxt, $dlTxt) -ForegroundColor $kolor
        }
    } finally {
        Write-Host "Zatrzymano. Log zapisany: $plik" -ForegroundColor Cyan
    }
}

function Test-AdminUstawmode {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PowercfgWartosc {
    param([string]$Alias)
    $ac = $null; $dc = $null
    foreach ($l in (powercfg /q SCHEME_CURRENT SUB_PROCESSOR $Alias)) {
        if ($l -match 'AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $ac = [Convert]::ToInt32($matches[1], 16) }
        elseif ($l -match 'DC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $dc = [Convert]::ToInt32($matches[1], 16) }
    }
    [pscustomobject]@{ AC = $ac; DC = $dc }
}

function Show-DiagnostykaUstawmode {
    function W([string]$Etykieta, [string]$Wartosc, [string]$Kolor = 'Gray') {
        Write-Host ('  {0,-28}' -f $Etykieta) -NoNewline
        Write-Host $Wartosc -ForegroundColor $Kolor
    }
    function N([string]$Tytul) { Write-Host ''; Write-Host "[$Tytul]" -ForegroundColor Cyan }

    $admin = Test-AdminUstawmode
    Write-Host ''
    Write-Host '=== Diagnostyka laptopa ===' -ForegroundColor Cyan
    if (-not $admin) { Write-Host '  (bez administratora nie widac zapisanego profilu BIOS)' -ForegroundColor DarkGray }

    # --- Zasilanie ---
    N 'Zasilanie'
    Add-Type -AssemblyName System.Windows.Forms
    $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
    $naZasilaczu = ($ps.PowerLineStatus -eq 'Online')
    $zrodlo = if ($naZasilaczu) { 'zasilacz' } else { 'BATERIA' }
    W 'Zrodlo zasilania' ("{0}, bateria {1}%" -f $zrodlo, [int]($ps.BatteryLifePercent * 100)) $(if ($naZasilaczu) { 'Green' } else { 'Yellow' })

    $plan = Get-PlanyZasilania | Where-Object Aktywny | Select-Object -First 1
    W 'Plan zasilania' $plan.Nazwa 'White'

    $ov = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -ErrorAction SilentlyContinue
    $ovGuid = if ($naZasilaczu) { $ov.ActiveOverlayAcPowerScheme } else { $ov.ActiveOverlayDcPowerScheme }
    $tryby = @{
        'ded574b5-45a0-4f42-8737-46345c09c238' = 'Najlepsza wydajnosc'
        '961cc777-2547-4f9d-8174-7d86181b8a7a' = 'Najlepsza efektywnosc energetyczna'
        '3af9b8d9-7c97-431d-ad78-34a8bfea439f' = 'Lepsza bateria'
        '00000000-0000-0000-0000-000000000000' = 'Zrownowazony'
    }
    $trybNazwa = if ($ovGuid -and $tryby.ContainsKey($ovGuid.ToLower())) { $tryby[$ovGuid.ToLower()] } elseif ($ovGuid) { $ovGuid } else { 'Zrownowazony' }
    W 'Tryb zasilania Windows' $trybNazwa

    $boostNazwy = @('Wylaczone', 'Wlaczone', 'Agresywne', 'Wlaczone wydajne', 'Agresywne wydajne', 'Agresywnie - gwarantowane', 'Wydajnosc: agresywnie - gwarantowane')
    $b = Get-PowercfgWartosc PERFBOOSTMODE
    $bTeraz = if ($naZasilaczu) { $b.AC } else { $b.DC }
    W 'Turbo Boost (plan)' ("zasilacz: {0} | bateria: {1}" -f $boostNazwy[$b.AC], $boostNazwy[$b.DC]) $(if ($bTeraz -gt 0) { 'Green' } else { 'Yellow' })
    $mx = Get-PowercfgWartosc PROCTHROTTLEMAX
    $mn = Get-PowercfgWartosc PROCTHROTTLEMIN
    W 'Stan procesora max / min' ("zasilacz: {0}% / {1}% | bateria: {2}% / {3}%" -f $mx.AC, $mn.AC, $mx.DC, $mn.DC)

    # --- Procesor ---
    N 'Procesor'
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    W 'Model' $cpu.Name.Trim()
    $pelny = ($cpu.NumberOfLogicalProcessors -ge 22)
    W 'Rdzenie / watki aktywne' ("{0} / {1}   (pelny procesor: 16 / 22)" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors) $(if ($pelny) { 'Green' } else { 'Yellow' })
    $profilTeraz = if ($pelny) { 'pelny' } elseif ($cpu.NumberOfLogicalProcessors -eq 6) { 'chlodny' } else { 'inny' }
    W 'Profil BIOS (dziala teraz)' $profilTeraz 'White'

    if ($admin) {
        try {
            $ust = @{}
            Get-CimInstance -Namespace root\wmi -ClassName Lenovo_BiosSetting -ErrorAction Stop |
                Where-Object CurrentSetting | ForEach-Object {
                    $c = $_.CurrentSetting -split ','
                    if ($global:UstawmodeBios.pelny.Ustawienia.Contains($c[0])) { $ust[$c[0]] = $c[1] }
                }
            $zapisany = 'mieszany'
            foreach ($k in $global:UstawmodeBios.Keys) {
                $zgodny = $true
                foreach ($n in $global:UstawmodeBios[$k].Ustawienia.Keys) {
                    if ($ust[$n] -ne $global:UstawmodeBios[$k].Ustawienia[$n]) { $zgodny = $false }
                }
                if ($zgodny) { $zapisany = $k }
            }
            $kolor = if ($zapisany -eq $profilTeraz) { 'White' } else { 'Yellow' }
            $dop = if ($zapisany -ne $profilTeraz) { '  <- wejdzie po restarcie' } else { '' }
            W 'Profil BIOS (zapisany)' "$zapisany$dop" $kolor
            foreach ($n in $global:UstawmodeBios.pelny.Ustawienia.Keys) { W "  $n" $ust[$n] 'DarkGray' }
        } catch {
            W 'Profil BIOS (zapisany)' 'nie udalo sie odczytac' 'DarkGray'
        }
    } else {
        W 'Profil BIOS (zapisany)' 'wymaga administratora' 'DarkGray'
    }

    $zapytanie = { Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" }
    $null = & $zapytanie
    Start-Sleep -Milliseconds 1000
    $perf = & $zapytanie
    if ($perf) {
        $mhz = [Math]::Round($perf.ProcessorFrequency * $perf.PercentProcessorPerformance / 100)
        W 'Taktowanie teraz' ("{0} MHz   (bazowe {1} MHz)" -f $mhz, $cpu.MaxClockSpeed) 'White'
        $turbo = if ($mhz -gt $cpu.MaxClockSpeed * 1.05) { 'TAK - procesor przekracza taktowanie bazowe' } else { 'nie (brak obciazenia albo turbo wylaczone)' }
        W 'Turbo dziala w tej chwili' $turbo $(if ($mhz -gt $cpu.MaxClockSpeed * 1.05) { 'Green' } else { 'DarkGray' })
        W 'Obciazenie CPU' ("{0}%" -f $perf.PercentProcessorTime)
    }

    $tz = @(Get-TemperaturyUstawmode)
    if ($tz.Count -gt 0) {
        foreach ($z in $tz) {
            $kol = if ($z.C -ge 95) { 'Red' } elseif ($z.C -ge 85) { 'Yellow' } else { 'Green' }
            $dl = if ($z.Dlawienie -gt 0) { "  DLAWIENIE $($z.Dlawienie)%" } else { '  (bez dlawienia)' }
            W "Temperatura ($($z.Strefa))" ("{0} C{1}" -f $z.C, $dl) $kol
        }
    } else {
        W 'Temperatura' 'niedostepna' 'DarkGray'
    }

    # --- Karta graficzna ---
    N 'Karta graficzna'
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $g = (nvidia-smi --query-gpu=name,pstate,temperature.gpu,utilization.gpu,power.draw,clocks.gr,memory.used,memory.total --format=csv,noheader,nounits | Select-Object -First 1) -split ',\s*'
        W 'Model' $g[0]
        $stan = if ($g[1] -eq 'P8') { 'P8 (spoczynek)' } elseif ($g[1] -eq 'P0') { 'P0 (pelna moc)' } else { $g[1] }
        W 'Stan / obciazenie' ("{0}, {1}%" -f $stan, $g[3])
        W 'Temperatura / pobor' ("{0} C, {1} W" -f $g[2], $g[4])
        W 'Taktowanie rdzenia' ("{0} MHz" -f $g[5])
        W 'Pamiec VRAM' ("{0} / {1} MB" -f $g[6], $g[7])
    } else {
        W 'NVIDIA' 'brak nvidia-smi' 'DarkGray'
    }

    # --- Pamiec, WSL, dysk ---
    N 'Pamiec i system'
    $os = Get-CimInstance Win32_OperatingSystem
    $calosc = $os.TotalVisibleMemorySize / 1MB
    $wolne = $os.FreePhysicalMemory / 1MB
    W 'RAM uzyte / calosc' ("{0:N1} / {1:N1} GB" -f ($calosc - $wolne), $calosc)

    $vm = Get-Process vmmemWSL -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vm) {
        W 'WSL' ("DZIALA, zajmuje {0:N1} GB RAM  (przed gra: wsl --shutdown)" -f ($vm.WorkingSet64 / 1GB)) 'Yellow'
    } else {
        W 'WSL' 'wylaczony' 'Green'
    }
    $cfg = "$env:USERPROFILE\.wslconfig"
    if (Test-Path $cfg) {
        $lim = (Get-Content $cfg | Where-Object { $_ -match '^\s*(memory|processors)\s*=' }) -join ', '
        if ($lim) { W 'Limity WSL (.wslconfig)' $lim 'DarkGray' }
    }

    $c = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($c) {
        $wolneC = $c.Free / 1GB
        W 'Wolne miejsce na C:' ("{0:N0} GB" -f $wolneC) $(if ($wolneC -lt 220) { 'Yellow' } else { 'Green' })
    }
    Write-Host ''
}

function Select-TrybUstawmode {
    param([object[]]$Tryby)
    $i = 0
    for ($k = 0; $k -lt $Tryby.Count; $k++) { if ($Tryby[$k].Aktywny -and $Tryby[$k].Typ -eq 'plan') { $i = $k } }

    # Bez interaktywnej konsoli: zwykla lista numerowana
    if ($Host.Name -ne 'ConsoleHost' -or [Console]::IsInputRedirected) {
        for ($k = 0; $k -lt $Tryby.Count; $k++) {
            $m = if ($Tryby[$k].Aktywny) { ' (aktywny)' } else { '' }
            Write-Host ("  {0}. {1}{2}" -f ($k + 1), $Tryby[$k].Nazwa, $m)
        }
        $n = 0
        if ([int]::TryParse((Read-Host 'Numer'), [ref]$n) -and $n -ge 1 -and $n -le $Tryby.Count) {
            return $Tryby[$n - 1]
        }
        return $null
    }

    Write-Host 'Wybierz tryb (strzalki + Enter, cyfra, Esc = anuluj):' -ForegroundColor Yellow
    $szer = [Math]::Max(40, [Console]::WindowWidth - 1)
    foreach ($t in $Tryby) { Write-Host '' }
    $top = [Console]::CursorTop - $Tryby.Count
    $kursor = [Console]::CursorVisible
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            [Console]::SetCursorPosition(0, $top)
            for ($k = 0; $k -lt $Tryby.Count; $k++) {
                $m = if ($Tryby[$k].Aktywny) { '  (aktywny)' } else { '' }
                $z = if ($k -eq $i) { '>' } else { ' ' }
                $linia = ("{0} {1}. {2}{3}" -f $z, ($k + 1), $Tryby[$k].Nazwa, $m)
                if ($linia.Length -gt $szer) { $linia = $linia.Substring(0, $szer) }
                $linia = $linia.PadRight($szer)
                if ($k -eq $i) { Write-Host $linia -ForegroundColor Black -BackgroundColor Cyan }
                else { Write-Host $linia }
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $i = ($i - 1 + $Tryby.Count) % $Tryby.Count }
                'DownArrow' { $i = ($i + 1) % $Tryby.Count }
                'Enter'     { return $Tryby[$i] }
                'Escape'    { return $null }
                default {
                    $n = 0
                    if ([int]::TryParse([string]$key.KeyChar, [ref]$n) -and $n -ge 1 -and $n -le $Tryby.Count) {
                        return $Tryby[$n - 1]
                    }
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $kursor
    }
}

function Set-PlanUstawmode {
    param([string]$Guid, [string]$Nazwa)
    powercfg /setactive $Guid
    if ($LASTEXITCODE -eq 0) { Write-Host "Ustawiono plan: $Nazwa" -ForegroundColor Green }
    else { Write-Host "Nie udalo sie przelaczyc na: $Nazwa" -ForegroundColor Red }
}

function Set-BiosUstawmode {
    param([string]$Klucz)
    $profil = $global:UstawmodeBios[$Klucz]

    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        Write-Host 'Zmiana BIOS wymaga administratora - otwieram okno z uprawnieniami (potwierdz w UAC)...' -ForegroundColor Yellow
        Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoExit', '-Command', "ustawmode $Klucz")
        return
    }

    try {
        $bios = Get-WmiObject -Namespace root\wmi -Class Lenovo_SetBiosSetting -ErrorAction Stop
    } catch {
        Write-Host 'Brak interfejsu Lenovo WMI BIOS.' -ForegroundColor Red
        return
    }

    foreach ($nazwa in $profil.Ustawienia.Keys) {
        $wartosc = $profil.Ustawienia[$nazwa]
        $wynik = $bios.SetBiosSetting("$nazwa,$wartosc").return
        if ($wynik -ne 'Success') {
            Write-Host "  $nazwa = $wartosc -> $wynik. Przerywam, nic nie zapisano." -ForegroundColor Red
            return
        }
        Write-Host "  $nazwa = $wartosc" -ForegroundColor DarkGray
    }

    $zapis = (Get-WmiObject -Namespace root\wmi -Class Lenovo_SaveBiosSettings).SaveBiosSettings().return
    if ($zapis -ne 'Success') {
        Write-Host "Zapis BIOS nie powiodl sie: $zapis" -ForegroundColor Red
        return
    }
    Write-Host "Zapisano profil BIOS: $Klucz (zadziala po restarcie)" -ForegroundColor Green

    $plan = Get-PlanyZasilania | Where-Object { $_.Guid -eq $profil.Plan } | Select-Object -First 1
    if ($plan) { Set-PlanUstawmode -Guid $plan.Guid -Nazwa $plan.Nazwa }

    $odp = Read-Host 'Zrestartowac teraz? (t/N)'
    if ($odp -match '^(t|tak|y)$') { Restart-Computer }
    else { Write-Host 'Pamietaj o restarcie (Uruchom ponownie, nie Zamknij).' -ForegroundColor Yellow }
}

function ustawmode {
    param(
        [Parameter(Position = 0)]
        [ArgumentCompleter({
            param($cmd, $param, $slowo)
            $slowo = $slowo.Trim("'", '"')
            @('normalny', 'diagnostyka', 'logowanie') + @($global:UstawmodeBios.Keys) + @((Get-PlanyZasilania).Nazwa) |
                Where-Object { $_ -like "$slowo*" } |
                ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } }
        })]
        [string]$Tryb,

        [Parameter(Position = 1)]
        [int]$Interwal = 5
    )

    if ($Tryb -and 'logowanie' -like "$($Tryb.ToLower())*" -and $Tryb.Length -ge 3) {
        Start-LogowanieUstawmode -Interwal $Interwal
        return
    }

    if ($Tryb -and 'diagnostyka' -like "$($Tryb.ToLower())*" -and $Tryb.Length -ge 4) {
        Show-DiagnostykaUstawmode
        return
    }

    if ($Tryb -and $global:UstawmodeBios.Contains($Tryb.ToLower())) {
        Set-BiosUstawmode -Klucz $Tryb.ToLower()
        return
    }

    $plany = @(Get-PlanyZasilania)

    if (-not $Tryb) {
        $wybor = Select-TrybUstawmode -Tryby @(Get-TrybyUstawmode)
        if (-not $wybor) { Write-Host 'Anulowano.' -ForegroundColor DarkGray; return }
        if ($wybor.Typ -eq 'bios') { Set-BiosUstawmode -Klucz $wybor.Klucz; return }
        if ($wybor.Typ -eq 'diag') { Show-DiagnostykaUstawmode; return }
        if ($wybor.Typ -eq 'log') { Start-LogowanieUstawmode -Interwal $Interwal; return }
    } elseif ($Tryb -eq 'normalny') {
        $wybor = $plany | Where-Object { $_.Guid -eq '381b4222-f694-41f0-9685-ff5bb260df2e' } | Select-Object -First 1
    } else {
        $wybor = $plany | Where-Object { $_.Nazwa -eq $Tryb } | Select-Object -First 1
        if (-not $wybor) { $wybor = $plany | Where-Object { $_.Nazwa -like "$Tryb*" } | Select-Object -First 1 }
    }

    if (-not $wybor) {
        $dostepne = @('normalny', 'diagnostyka', 'logowanie') +@($global:UstawmodeBios.Keys) + @($plany.Nazwa)
        Write-Host "Nie ma trybu '$Tryb'. Dostepne: $($dostepne -join ', ')" -ForegroundColor Red
        return
    }

    Set-PlanUstawmode -Guid $wybor.Guid -Nazwa $wybor.Nazwa
}
