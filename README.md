# runAI

Balss diktēšana Mac datoriem latviešu, latgaliešu un angļu valodā.

Turi nospiestu labo `Option` taustiņu, runā un atlaid. Teksts uzreiz parādās tur, kur ir kursors. Ja kursors tobrīd nav teksta laukā, lietotne saglabā tekstu starpliktuvē, lai vari to ielīmēt ar `⌘V`.

Visa balss atpazīšana notiek lokāli tavā datorā ar `whisper.cpp`. Audio ieraksti paliek operatīvajā atmiņā tikai dažas sekundes apstrādes laikā un nekur netiek sūtīti. Internets vajadzīgs tikai vienu reizi, lai lejupielādētu valodas modeli.

Mājaslapa: [runai.ciematnieks.lv](https://runai.ciematnieks.lv)

## Kāpēc es šo uztaisīju

Lielākā daļa diktēšanas rīku labi saprot angļu valodu, bet latviski regulāri jauc galotnes vai izdomā neesošus vārdus. Tie, kas strādā puslīdz ciešami, parasti sūta balsi uz mākoņserveriem un prasa ikmēneša abonementu.

LU MII Mākslīgā intelekta laboratorija (AiLab) ir uztrenējusi tiešām labus atvērtā koda Whisper modeļus latviešu un latgaliešu valodai. Uz Apple Silicon (M sērijas procesori) tie darbojas lokāli un atšifrē teikumu pāris simtos milisekunžu. Atliek tikai ērts veids, kā tos izsaukt ar vienu taustiņu jebkurā programmā. Tam arī tapa runAI.

## Prasības

- macOS 14.0 (Sonoma) vai jaunāka versija.
- Apple Silicon procesors (M sērija).
- Sistēmas atļaujas:
  - macOS 14: *Accessibility* (universālā piekļuve) un *Microphone*.
  - macOS 15 (Sequoia) un jaunākas: papildus arī *Input Monitoring* (ievades pārraudzība), lai lietotne dzirdētu karsto taustiņu fonā.

*Piezīme: lietotne ir rakstīta natīvajā macOS (Swift) vidē, portēt uz Windows nav plānots.*

## Uzstādīšana

1. Lejupielādē jaunāko `runAI.dmg` no [Releases](https://github.com/kaspars1985/runAI/releases) vai [runai.ciematnieks.lv](https://runai.ciematnieks.lv).
2. Atver `.dmg` un ievelc `runAI` mapē `Applications`.
3. Tā kā lietotne nav parakstīta ar maksas Apple Developer kontu, pirmajā reizē macOS rādīs brīdinājumu. Atver *System Settings -> Privacy & Security* un nospied *Open Anyway*, vai terminālī izpildi:
   ```bash
   xattr -cr /Applications/runAI.app
   ```
4. Augšējā izvēlnes joslā (menu bar) nospied uz runAI ikonas un atver **Iestatījumi**:
   - Sadaļā **Atļaujas** piešķir prasītās piekļuves.
   - Sadaļā **Modeļi** lejupielādē modeli savai ikdienas valodai.

Ja pēc lietotnes atjaunināšanas macOS joprojām rāda, ka *Accessibility* atļauja ir ieslēgta, bet teksts automātiski neievietojas, iestatījumu logā nospied **Atiestatīt atļauju** un ieslēdz to no jauna (macOS mēdz saglabāt vecās versijas kontrolsummu).

## Kuru modeli izvēlēties

Modeļi glabājas mapē `~/Library/Application Support/runAI/Models/`. Tos var lejupielādēt tieši no lietotnes iestatījumiem:

- **AiLab Large v3 LV (q8)** (~1.6 GB) – visprecīzākais modelis latviešu valodai. Trenēts uz latviešu mediju un Common Voice ierakstiem.
- **AiLab Large v3 LV (q5)** (~1.0 GB) – mazāka latviešu modeļa versija, ja gribas ietaupīt vietu uz diska.
- **AiLab Large v3 Latgalian (q8)** (~1.6 GB) – LU MII modelis latgaliešu runai un rakstībai (MuLaR + CV20).
- **Large v3 Turbo (q8)** (~874 MB) – OpenAI modelis. Ātrs un precīzs angļu valodai un citām svešvalodām.
- **Large v3 Turbo (q5)** (~547 MB) – vieglākā Turbo versija ikdienai.

Ja tev datorā jau ir cits Whisper `.bin` (GGML) fails, vari to pievienot ar pogu *Pievienot savu .bin failu…*.

## Būvēšana no pirmkoda

Vajadzēs macOS ar Xcode Command Line Tools.

```bash
git clone https://github.com/kaspars1985/runAI.git
cd runAI

./build.sh
./create_dmg.sh
```

Skripts saknes mapē izveidos gatavu `runAI.app` un `runAI.dmg`.

## Koda struktūra

```text
Sources/
  RunAIApp.swift        – izvēlnes josla un logu vadība
  AppState.swift        – lietotnes stāvoklis un notikumu plūsma
  SettingsView.swift    – iestatījumu logs
  HUDController.swift   – peldošais ieraksta indikators ekrānā
  Models.swift          – modeļu saraksts un konfigurācija
  ModelManager.swift    – modeļu lejupielāde no Hugging Face
  WhisperEngine.swift   – whisper.cpp C++ saistījums
  AudioRecorder.swift   – mikrofona ieraksts (16 kHz PCM mono)
  HotkeyMonitor.swift   – globālā taustiņa tveršana (CGEventTap)
  TextInserter.swift    – teksta ievietošana aktīvajā logā vai starpliktuvē
  UpdateChecker.swift   – jaunu versiju pārbaude GitHub
  AudioDevices.swift    – mikrofonu saraksts un pārslēgšana
  KeyLabel.swift        – taustiņu nosaukumi
Frameworks/
  whisper.framework     – sakompilēta whisper.cpp bibliotēka Apple Silicon čipiem
```

## Izmaiņu vēsture

- **v2.4.2** – pievienots latgaliešu valodas modelis `AiLab Large v3 Latgalian (q8)` un latgaliešu valodas izvēle iestatījumos.
- **v2.4.1** – izvēlnes joslā rāda pašreiz aktīvo mikrofonu; īsāki HUD statusa paziņojumi.
- **v2.4.0** – iespēja novietot HUD indikatoru ekrāna centrā vai augšpusē.
- **v2.3.0** – izvēles ekrāna fona izpludināšana (*blur*) diktēšanas laikā.
- **v2.2.0** – jauns tumšā stikla HUD dizains ar skaņas viļņu indikatoru un hronometru.
- **v2.1.0** – atsevišķa atļauju loģika macOS 14 un macOS 15+ (*Input Monitoring*); salabota automātiskā teksta ievietošana pārlūkos un Electron lietotnēs (Slack, Discord, VS Code).
- **v2.0.0** – samazināta mikrofona ieslēgšanās aizture (vairs nenorij pirmo vārdu), noņemts viena teikuma ierobežojums, pievienots īso klikšķu (<300 ms) filtrs un Unicode NFC normalizācija latviešu garumzīmēm.
- **v1.2.0** – rezerves kopija starpliktuvē (`⌘V`), ja kursors neatrodas teksta laukā.
- **v1.1.0** – automātiska AirPods un ārējo mikrofonu pārslēgšana.
- **v1.0.0** – pirmā versija ar LU MII AiLab latviešu modeli un Metal GPU atbalstu.

## Pateicības un licences

Paša `runAI` pirmkods ir pieejams ar MIT licenci. Lietotne izmanto:

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (MIT licence), autors Georgi Gerganov.
- [LU MII Mākslīgā intelekta laboratorijas (AiLab)](https://huggingface.co/AiLab-IMCS-UL) trenētos modeļus (Apache 2.0 licence):
  - [latviešu valodas modeli](https://huggingface.co/AiLab-IMCS-UL/whisper-large-v3-lv-late-cv19);
  - [latgaliešu valodas modeli](https://huggingface.co/AiLab-IMCS-UL/whisper-large-v3-latgalian-2503).
- *TalkMe* projektu kā sākotnējo iedvesmu.
