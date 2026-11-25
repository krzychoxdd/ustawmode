# ustawmode

Jedna komenda PowerShell do przełączania trybu pracy laptopa z Windows:

- **plany zasilania** (np. „Gra” z turbo albo „Zrównoważony” na co dzień), przełączane od razu,
- **profile procesora w BIOS-ie** ThinkPada (chłodny: 6 rdzeni bez HT, albo pełna moc), zmieniane przez Lenovo WMI i działające po restarcie,
- **diagnostyka**, czyli jak laptop pracuje w tej chwili: turbo, rdzenie, taktowanie, temperatura, GPU, RAM, WSL i dysk,
- **logowanie temperatur** do pliku CSV na pulpicie co kilka sekund.

Wybierasz z menu strzałkami albo wpisujesz tryb wprost: `ustawmode gra`.

---

## Wymagania

| | |
|---|---|
| System | Windows 10 / 11 |
| Powłoka | Windows PowerShell 5.1 (wbudowany) albo PowerShell 7 |
| Profile BIOS | ThinkPad z interfejsem **Lenovo WMI BIOS** (`root\wmi\Lenovo_SetBiosSetting`) i uprawnienia administratora |
| GPU (opcjonalnie) | Karta NVIDIA z `nvidia-smi`; bez niej sekcja GPU jest pomijana |

Testowane na: **ThinkPad P1 Gen 7** (Intel Core Ultra 9 185H, RTX 4070 Laptop, 64 GB RAM).

> **GitHub Codespaces:** Codespace działa na Linuksie, więc skryptu tam **nie uruchomisz**: nie ma tam `powercfg`, WMI ani BIOS-u laptopa. W Codespace edytujesz i commitujesz kod, a uruchamiasz go na swoim Windowsie po `git clone` / `git pull`.

---

## Instalacja

### 1. Pobierz repozytorium na Windows

```powershell
git clone https://github.com/<twoj-login>/ustawmode.git C:\Tools\ustawmode
```

Jeśli pobierasz pliki ręcznie (ZIP, przeglądarka), odblokuj skrypt:

```powershell
Unblock-File C:\Tools\ustawmode\ustawmode.ps1
```

### 2. Zezwól na uruchamianie lokalnych skryptów (jednorazowo)

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### 3. Udostępnij komendę wszędzie

Wybierz **jeden** z dwóch sposobów.

#### Sposób A: folder w PATH

Skrypt definiuje funkcję `ustawmode`. Żeby działał uruchamiany z PATH (jako plik), musi ją na końcu wywołać. Dopisz na końcu `ustawmode.ps1`:

```powershell
# Uruchomione jako plik (z PATH) -> wykonaj; wczytane kropka (. .\ustawmode.ps1) -> tylko zdefiniuj funkcje
if ($MyInvocation.InvocationName -ne '.') {
    ustawmode @args
}
```

Następnie dodaj folder do zmiennej PATH użytkownika (nie wymaga administratora):

```powershell
$dir = 'C:\Tools\ustawmode'
$path = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($path -split ';') -notcontains $dir) {
    [Environment]::SetEnvironmentVariable('Path', "$path;$dir", 'User')
}
```

Zamknij i otwórz terminal, a potem sprawdź:

```powershell
Get-Command ustawmode
```

Powinien wskazać `C:\Tools\ustawmode\ustawmode.ps1`. Komenda działa w każdym oknie PowerShell, także w Windows Terminal i VS Code.

#### Sposób B: profil PowerShell (działa bez zmian w skrypcie, Tab podpowiada tryby)

Wczytuje funkcję przy każdym starcie PowerShell:

```powershell
Add-Content -Path $PROFILE.CurrentUserAllHosts -Value ". 'C:\Tools\ustawmode\ustawmode.ps1'"
```

Jeśli ustawisz oba sposoby, wygrywa funkcja z profilu.

### 4. Utwórz plan zasilania „Gra” (jednorazowo)

Profil `pelny` przełącza na plan **Gra**, zapisany w skrypcie przez swój GUID (`Plan = '...'` w `$global:UstawmodeBios`). Na nowym komputerze utwórz plan jako kopię „Zrównoważonego” z włączonym turbo (tryb „Włączone wydajne”) na zasilaczu, a wypisany GUID wpisz do skryptu:

```powershell
$guid = ((powercfg /duplicatescheme SCHEME_BALANCED) -split '\s+' | Where-Object { $_ -match '^[0-9a-f-]{36}$' })[0]
powercfg /changename $guid "Gra"
powercfg /setacvalueindex $guid SUB_PROCESSOR PERFBOOSTMODE 3
powercfg /setdcvalueindex $guid SUB_PROCESSOR PERFBOOSTMODE 0
$guid
```

Wartości `PERFBOOSTMODE`: `0` wyłączone, `1` włączone, `2` agresywne, `3` włączone wydajne, `4` agresywne wydajne.

---

## Użycie

### Menu

```text
PS C:\> ustawmode
Wybierz tryb (strzalki + Enter, cyfra, Esc = anuluj):
> 1. Gra  (aktywny)
  2. Zrównoważony
  3. BIOS: chlodny (6 rdzeni, cicho) - wymaga restartu
  4. BIOS: pelna moc (16 rdzeni / 22 watki) - wymaga restartu  (aktywny)
  5. Diagnostyka - jak teraz pracuje laptop
  6. Logowanie temperatur na pulpit (co 5 s, Ctrl+C = stop)
```

- **↑ / ↓ + Enter** wybiera pozycję, **cyfra** wybiera od razu, **Esc** anuluje.
- Na liście są **wszystkie** plany zasilania z systemu, także te dodane później.
- `(aktywny)` przy planie oznacza plan włączony teraz. Przy profilu BIOS oznacza konfigurację procesora, na której system **działa w tej chwili** (rozpoznaną po liczbie wątków).

### Komendy bezpośrednie

| Komenda | Co robi | Kiedy działa |
|---|---|---|
| `ustawmode` | Menu wyboru | – |
| `ustawmode gra` | Włącza plan zasilania „Gra” | od razu |
| `ustawmode normalny` | Włącza plan „Zrównoważony” | od razu |
| `ustawmode <nazwa planu>` | Dowolny plan, wystarczy początek nazwy (`ustawmode zr`) | od razu |
| `ustawmode chlodny` | BIOS: profil chłodny i plan „Zrównoważony” | po restarcie |
| `ustawmode pelny` | BIOS: pełna moc i plan „Gra” | po restarcie |
| `ustawmode diagnostyka` | Raport o bieżącej pracy laptopa | od razu |
| `ustawmode logowanie` | Log temperatur co 5 s do CSV na pulpicie | do Ctrl+C |
| `ustawmode logowanie 10` | To samo, co 10 s | do Ctrl+C |

**Tab** podpowiada wszystkie tryby i nazwy planów.

### Profile BIOS

| Ustawienie BIOS | `chlodny` | `pelny` |
|---|---|---|
| `HyperThreadingTechnology` | Disable | Enable |
| `EfficientCores` | Disable | Enable |
| `CPUPowerManagement` | Disable | Enable |
| `EnergyEfficientTurbo` | Disable | Enable |
| Wynik na Ultra 9 185H | 6 rdzeni / 6 wątków | 16 rdzeni / 22 wątki |
| Plan zasilania | Zrównoważony | Gra |

Jak to działa:

1. Bez uprawnień administratora skrypt sam otwiera okno z uprawnieniami. Potwierdzasz tylko okno UAC.
2. Ustawia każdą opcję przez `Lenovo_SetBiosSetting`. Jeśli któraś zwróci coś innego niż `Success`, przerywa i **niczego nie zapisuje**.
3. Zapisuje zmiany przez `Lenovo_SaveBiosSettings` i przełącza plan zasilania.
4. Pyta: `Zrestartowac teraz? (t/N)`.

> ⚠️ **Przed pierwszą zmianą BIOS-u** miej pod ręką klucz odzyskiwania BitLockera (<https://aka.ms/myrecoverykey>). Zmiana ustawień BIOS-u może sprawić, że system poprosi o niego przy starcie.
> Używaj opcji **Uruchom ponownie**, nie „Zamknij”. Szybkie uruchamianie może pominąć część ponownej inicjalizacji.
> Jeśli BIOS ma hasło administratora, WMI zwróci `Access Denied`. Wtedy zmień ustawienia ręcznie: F1 przy starcie, potem Config → CPU.

### Diagnostyka

```text
PS C:\> ustawmode diagnostyka

=== Diagnostyka laptopa ===
  (bez administratora nie widac zapisanego profilu BIOS)

[Zasilanie]
  Zrodlo zasilania            zasilacz, bateria 64%
  Plan zasilania              Gra
  Tryb zasilania Windows      Najlepsza wydajnosc
  Turbo Boost (plan)          zasilacz: Wlaczone wydajne | bateria: Wylaczone
  Stan procesora max / min    zasilacz: 100% / 5% | bateria: 100% / 5%

[Procesor]
  Model                       Intel(R) Core(TM) Ultra 9 185H
  Rdzenie / watki aktywne     16 / 22   (pelny procesor: 16 / 22)
  Profil BIOS (dziala teraz)  pelny
  Profil BIOS (zapisany)      wymaga administratora
  Taktowanie teraz            3740 MHz   (bazowe 2300 MHz)
  Turbo dziala w tej chwili   TAK - procesor przekracza taktowanie bazowe
  Obciazenie CPU              6%
  Temperatura (THM0)          74,1 C  (bez dlawienia)

[Karta graficzna]
  Model                       NVIDIA GeForce RTX 4070 Laptop GPU
  Stan / obciazenie           P3, 0%
  Temperatura / pobor         41 C, 17.96 W
  Taktowanie rdzenia          1695 MHz
  Pamiec VRAM                 0 / 8188 MB

[Pamiec i system]
  RAM uzyte / calosc          13,3 / 63,4 GB
  WSL                         DZIALA, zajmuje 2,1 GB RAM  (przed gra: wsl --shutdown)
  Limity WSL (.wslconfig)     memory=48GB, processors=12
  Wolne miejsce na C:         56 GB
```

Kolory: **zielony** oznacza, że jest dobrze. **Żółty** to ostrzeżenie: bateria, wyłączone turbo, przycięte rdzenie, działający WSL, mało miejsca albo profil BIOS-u, który wejdzie dopiero po restarcie. **Czerwony** oznacza temperaturę od 95 °C.
Uruchomiona jako administrator pokazuje też **zapisany** profil BIOS-u i każde z czterech ustawień.

### Logowanie temperatur

```text
PS C:\> ustawmode logowanie
Logowanie co 5 s do: C:\Users\<uzytkownik>\Desktop\temperatury_2026-11-25_15-07-00.csv
Zatrzymanie: Ctrl+C
(temperatura CPU = czujnik ACPI z Windows; jest nizsza i wolniejsza niz "Package" w HWiNFO)
15:07:06  CPU 63,1 C  3620 MHz  3% | GPU 47 C 0%
15:07:12  CPU 66,1 C  3940 MHz  23% | GPU 47 C 0%
15:07:18  CPU 87,1 C  3680 MHz  12% | GPU 49 C 0%
15:07:23  CPU 88,1 C  2620 MHz  10% | GPU 49 C 0%
15:07:29  CPU 72,1 C  3140 MHz  5% | GPU 49 C 0%
```

Każde uruchomienie tworzy na pulpicie nowy plik `temperatury_RRRR-MM-DD_GG-MM-SS.csv`. Plik ma separator `;` i przecinek dziesiętny, więc otwiera się od razu w polskim Excelu.

| Kolumna | Opis |
|---|---|
| `Czas` | Data i godzina próbki |
| `Zasilanie`, `Bateria_proc` | Zasilacz albo bateria, poziom naładowania |
| `Plan` | Aktywny plan zasilania |
| `CPU_MHz`, `CPU_obciazenie_proc` | Rzeczywiste taktowanie i obciążenie procesora |
| `CPU_temp_<strefa>_C` | Temperatura ze strefy termicznej ACPI |
| `Dlawienie_<strefa>_proc` | O ile % Windows zwalnia procesor z powodu temperatury (0 = bez dławienia) |
| `GPU_temp_C`, `GPU_W`, `GPU_obciazenie_proc`, `GPU_MHz` | Dane z `nvidia-smi` |
| `RAM_uzyte_GB` | Zajęta pamięć RAM |

Rzeczywisty odstęp między próbkami jest ok. 1 s dłuższy od ustawionego, bo tyle trwa odczyt czujników.

---

## Dostosowanie

Profile BIOS są zdefiniowane na początku `ustawmode.ps1` w `$global:UstawmodeBios`:

```powershell
pelny = @{
    Nazwa      = 'BIOS: pelna moc (16 rdzeni / 22 watki) - wymaga restartu'
    Watki      = 22        # po tej liczbie watkow skrypt rozpoznaje aktywny profil
    Plan       = '14c57240-...'   # GUID planu zasilania "Gra"
    Ustawienia = [ordered]@{ HyperThreadingTechnology = 'Enable'; ... }
}
```

Na innym komputerze wpisz GUID swojego planu „Gra” (`powercfg /list`). Na innym procesorze zmień też `Watki` i opis. Dostępne ustawienia BIOS-u oraz ich bieżące wartości wyświetlisz jako administrator:

```powershell
Get-CimInstance -Namespace root\wmi -ClassName Lenovo_BiosSetting | Where-Object CurrentSetting | ForEach-Object CurrentSetting
```

---

## Ograniczenia

- **Temperatura CPU** pochodzi z czujnika ACPI (`Thermal Zone Information`), który Windows udostępnia bez administratora. Jest niższa i wolniejsza niż „CPU Package” w HWiNFO. Pokazuje trend, ale nie łapie krótkich skoków. Do dokładnych pomiarów użyj logowania w HWiNFO.
- Odczyty mocy GPU powyżej 200 W są odrzucane jako błędne próbki sterownika.
- Profile BIOS-u działają tylko na ThinkPadach z Lenovo WMI. Na innych laptopach plany zasilania, diagnostyka i logowanie działają normalnie.

---

## Odinstalowanie

Usuń folder z PATH:

```powershell
$dir = 'C:\Tools\ustawmode'
$path = ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ -and $_ -ne $dir }) -join ';'
[Environment]::SetEnvironmentVariable('Path', $path, 'User')
```

Jeśli używałeś profilu, usuń z `$PROFILE.CurrentUserAllHosts` linię `. 'C:\Tools\ustawmode\ustawmode.ps1'`, a potem skasuj folder repozytorium.
