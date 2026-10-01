# Bosch-Kamera auf dem Apple TV

Native tvOS-App (Swift, SwiftUI, AVPlayer), die den Live-Stream einer **Bosch Eyes Outdoor II (Gen2)** auf dem Apple TV anzeigt. Den Stream liefert **Home Assistant**. Die App spricht nie direkt mit der Bosch-Cloud.

```
Bosch Eyes Outdoor II ──▶ Home Assistant ──▶ HLS-Stream (.m3u8) ──▶ tvOS-App ──▶ Apple TV
```

Keine externen Abhängigkeiten, nur Apple-Frameworks.

## Funktionsumfang (Phase 1 – MVP)

- Startseite „Meine Kameras“ mit großen, fokussierbaren Kacheln (10-foot UI, Dark Mode)
- Die zuletzt genutzte Kamera öffnet sich beim Start direkt (abschaltbar)
- Vollbild-Livebild über `AVPlayer`/`AVPlayerLayer`, ohne Transportleiste
- Play/Pause per Siri Remote. Nach einer Pause geht es am Live-Rand weiter.
- Automatischer Reconnect mit exponentiellem Backoff bei temporären Fehlern
- Klare Lade- und Fehlerzustände (siehe [Zustände](#zustände--fehler))
- Wechsel in den Hintergrund: Der Stream wird beendet und bei Rückkehr automatisch neu gestartet.
- Kameras kommen aus einer lokalen JSON-Datei. Stream-URLs lassen sich in der App überschreiben (UserDefaults).
- Logging über OSLog
- Die Architektur ist für die spätere Home-Assistant-Anbindung vorbereitet (`CameraProvider`, `StreamURLResolving`, Keychain).

## Voraussetzungen

| | |
|---|---|
| Xcode | **26 oder neuer** (Projektformat mit synchronisierten Ordnern, Deployment Target tvOS 26.0) |
| Gerät | Apple-TV-Simulator oder Apple TV (HD/4K) mit tvOS 26 |
| Stream | HLS-Stream (`.m3u8`) über http(s), z. B. aus Home Assistant oder go2rtc |

Wenn deine Xcode-Version neuere tvOS-Versionen anbietet, kannst du `TVOS_DEPLOYMENT_TARGET` in den Projekteinstellungen anheben.

## Schnellstart (Simulator)

1. `BoschCameraTV.xcodeproj` in Xcode öffnen.
2. Scheme **BoschCameraTV** und einen *Apple TV*-Simulator wählen, dann ⌘R.
3. Ohne eigene Konfiguration erscheinen die Beispielkameras. Deren URLs sind Platzhalter, deshalb siehst du dort einen Fehlerzustand.
   Zum Ausprobieren der Wiedergabe: *Product → Scheme → Edit Scheme… → Run → Arguments* und dort das vorbereitete, deaktivierte Launch-Argument aktivieren. Es leitet „Haustür“ auf Apples öffentlichen HLS-Teststream um.

Tests: ⌘U oder

```sh
xcodebuild test -project BoschCameraTV.xcodeproj -scheme BoschCameraTV \
  -destination 'platform=tvOS Simulator,name=Apple TV'
```

## Auf einem echten Apple TV

1. Signing-Einstellungen lokal anlegen. Sie werden nicht eingecheckt:
   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```
   Trage dort `BUNDLE_ID_PREFIX` (z. B. `de.deinname`) und deine `DEVELOPMENT_TEAM`-ID ein. Wählst du das Team stattdessen in Xcode unter *Signing & Capabilities*, landet die Team-ID in der Projektdatei.
2. Apple TV koppeln: auf dem Apple TV unter *Einstellungen → Fernbedienungen und Geräte → Remote-App und Geräte*, in Xcode unter *Window → Devices and Simulators*.
3. Das Apple TV als Ziel wählen und ⌘R drücken.

## Kameras konfigurieren

### A) `Cameras.json` (empfohlen)

```sh
cp BoschCameraTV/Resources/Cameras.example.json BoschCameraTV/Resources/Cameras.json
```

`Cameras.json` steht in `.gitignore`. Xcode übernimmt die Datei automatisch ins App-Bundle (synchronisierter Ordner) und bevorzugt sie vor der Beispieldatei.

```json
[
  {
    "id": "front-door",
    "name": "Haustür",
    "streamURL": "http://homeassistant.local:1984/api/stream.m3u8?src=haustuer",
    "enabled": true
  }
]
```

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `id` | ja | Eindeutige ID, z. B. später die Entity-ID `camera.haustuer` |
| `name` | nein | Anzeigename (Standard: `id`) |
| `streamURL` | nein | HLS-URL (http/https). Leer heißt „nicht konfiguriert“. |
| `enabled` | nein | `false` blendet die Kamera aus (Standard: `true`) |

### B) In der App

*Meine Kameras → Einstellungen → Stream-URLs*: Eine URL pro Kamera überschreibt den Wert aus der Datei. Sie wird nur lokal in `UserDefaults` gespeichert. Ein leeres Feld setzt auf den Dateiwert zurück. Statt der Bildschirmtastatur kannst du auch ein iPhone im selben Netz zur Eingabe nutzen.

### C) Launch-Argument (Entwicklung)

```
-streamURLOverrides '{ "front-door" = "http://192.168.1.10:1984/api/stream.m3u8?src=haustuer"; }'
```

### Welche URL liefert Home Assistant?

AVPlayer spielt **HLS** über http(s). RTSP wird nicht unterstützt. Die Kamera muss deshalb als HLS bereitgestellt werden. Wie die Bosch-Kamera in Home Assistant eingebunden ist (Integration, go2rtc …), liegt außerhalb dieser App. Typische Quellen, je nach Setup:

| Quelle | Beispiel-URL | Hinweis |
|---|---|---|
| go2rtc (z. B. als Add-on) | `http://<host>:1984/api/stream.m3u8?src=<stream>` | Statische URL, für Phase 1 am einfachsten. Details stehen in der go2rtc-Dokumentation. |
| Stream-Integration von Home Assistant | `http://<ha>:8123/api/hls/<token>/master_playlist.m3u8` | Das Token vergibt Home Assistant per WebSocket-Befehl `camera/stream`. Es verfällt, sobald der Stream eine Weile ungenutzt ist. Phase 2 holt es automatisch (siehe Roadmap). |

Unverschlüsseltes `http://` ist für lokale Adressen (`*.local`, IP-Adressen, Hostnamen ohne Domain) und für AVFoundation-Medien freigegeben (`Config/Info.plist`). Für Zugriffe von außen solltest du `https://` verwenden.

## Bedienung (Siri Remote)

| Taste | Kameraauswahl | Livebild |
|---|---|---|
| Touchpad wischen | Fokus bewegen | Kameraname und Status kurz einblenden |
| Touchpad klicken | Kamera öffnen | Pause/Fortsetzen (im Fehlerfall: erneut versuchen) |
| Play/Pause | – | Pause/Fortsetzen (im Fehlerfall: erneut versuchen) |
| Menü/Zurück | App verlassen | Zurück zur Kameraauswahl |

## Zustände & Fehler

| Anzeige | Bedeutung |
|---|---|
| **Verbinde…** | Stream-URL wird ermittelt und der Server geprüft (kurze HTTP-Vorabprüfung) |
| **Stream wird geladen…** | Server antwortet, AVPlayer lädt bzw. puffert |
| **Verbindung wird wiederhergestellt…** | Automatischer Reconnect. Darunter stehen Ursache und Versuch *n* von 8. |
| **Keine Verbindung zu Home Assistant** | Netzwerkfehler (Host nicht erreichbar, Timeout, DNS …) |
| **Stream nicht verfügbar** | Server erreichbar, aber HTTP 404/5xx, ungültige Playlist, keine Bilddaten mehr oder Stream beendet |
| Zugriff verweigert / Keine bzw. ungültige Stream-URL | Konfigurationsfehler. Hier gibt es keinen automatischen Reconnect. |

- **Reconnect:** Temporäre Fehler werden mit Backoff 1 s, 2 s, 4 s, 8 s, 16 s, 30 s, 30 s, 30 s (±20 % Jitter) wiederholt. Danach erscheint der Fehler mit „Erneut versuchen“.
- **Watchdog:** Kommt 20 s nach dem Laden kein Bild oder puffert die Wiedergabe länger als 15 s, wird der Stream neu aufgebaut.
- **Pause:** Nach dem Fortsetzen springt die Wiedergabe zum Live-Rand. Nach mehr als 30 s Pause wird der Stream neu aufgebaut.
- **Hintergrund:** Der Stream wird vollständig beendet (Netzwerk und Decoder frei). Bei Rückkehr startet er automatisch neu.

## Architektur

MVVM mit austauschbaren Services. ViewModels hängen nur von Protokollen ab und sind ohne Netzwerk testbar.

```
BoschCameraTV/
├── App/
│   ├── BoschCameraTVApp.swift      Einstieg, Audio-Session
│   └── AppDependencies.swift       Komposition der konkreten Implementierungen
├── Models/
│   ├── Camera.swift                id, name, streamURL, enabled (+ URL-Validierung)
│   ├── PlayerState.swift           idle | loading | playing | paused | reconnecting | failed
│   └── StreamError.swift           Fehlerarten, Texte, Klassifizierung roher Fehler
├── Services/
│   ├── CameraProvider.swift        protocol CameraProvider { func cameras() async throws -> [Camera] }
│   ├── LocalCameraProvider.swift   Cameras.json → [Camera]
│   ├── CameraService.swift         Fassade: aktiv-Filter, Duplikate, URL-Overrides
│   ├── StreamURLResolver.swift     Stream-URL je Kamera (Phase 2: Home Assistant)
│   ├── StreamProbe.swift           HTTP-Vorabprüfung → präzise Fehlermeldungen
│   ├── StreamPlaying.swift         Player-Protokoll (für Tests)
│   ├── StreamPlayer.swift          AVPlayer, Reconnect/Backoff, Watchdog, Aufräumen
│   ├── RetryPolicy.swift           Exponentielles Backoff mit Jitter
│   ├── SettingsStore.swift         UserDefaults (keine Geheimnisse!)
│   ├── KeychainStore.swift         Keychain-Wrapper für Geheimnisse
│   └── HomeAssistant/              Vorbereitung Phase 2 (Token in der Keychain)
├── ViewModels/                     CameraList-, Player-, SettingsViewModel
├── Views/                          RootView, CameraListView, CameraPlayerView, SettingsView
│   └── Components/                 VideoSurfaceView (AVPlayerLayer), Kacheln, Overlays
├── Support/                        Log (OSLog), Preview-Daten
└── Resources/                      Assets (Icon, Top Shelf), Cameras.example.json
```

**StreamPlayer im Detail:**

```
start(camera) ─▶ loading/„Verbinde…“: Resolver → Vorabprüfung
                 └▶ loading/„Stream wird geladen…“: AVPlayerItem, Watchdog
                       └▶ playing ◀──▶ paused
Fehler ─▶ transient & Versuche übrig? ─ja─▶ reconnecting ─(Backoff)─▶ erneut verbinden
                                     └nein─▶ failed(StreamError)
```

- Genau **eine** `AVPlayer`-Instanz für die gesamte App. Pro Verbindungsversuch wird nur das `AVPlayerItem` getauscht.
- Jeder Verbindungsversuch bekommt eine *Generationsnummer*. Verspätete KVO- und Notification-Callbacks alter Items werden daran erkannt und verworfen.
- Beim Stoppen und vor jedem Reconnect werden Item, KVO-Beobachter, Notifications und Watchdog vollständig freigegeben.

## Logging

OSLog mit dem Bundle-Identifier als Subsystem und den Kategorien `App`, `Cameras`, `Player`, `Network` und `Settings`. In Console.app etwa nach `subsystem:com.example.BoschCameraTV category:Player` filtern. Stream-URLs können Tokens enthalten und werden deshalb nie öffentlich geloggt.

## Sicherheit

- Keine Zugangsdaten oder echten Adressen im Quellcode. `Cameras.json` und `Config/Local.xcconfig` stehen in `.gitignore`.
- Ein Home-Assistant-Token gehört ausschließlich in die Keychain. `KeychainStore` und `HomeAssistantCredentialStore` sind dafür vorbereitet und getestet.
- Stream-URL-Overrides liegen in `UserDefaults`. Das ist ein bewusster MVP-Kompromiss: HLS-Stream-Tokens sind kurzlebig, ein Long-Lived Access Token darf dort nie landen.
- ATS bleibt aktiv. Ausnahmen gelten nur für lokale Netze und AVFoundation-Medien.

## Tests

Unit-Tests mit Swift Testing (`BoschCameraTVTests/`):

- Modelle: JSON-Decoding und Defaults, URL-Validierung, Fehlerklassifizierung (auch in AVFoundation verpackte Netzwerkfehler)
- Services: `LocalCameraProvider`, `CameraService` (Filter, Duplikate, Overrides), `SettingsStore`, `RetryPolicy`, Status-Auswertung der Vorabprüfung, Keychain
- `StreamPlayer`: fehlende oder ungültige URL, keine Retries bei permanenten Fehlern, Backoff-Reconnects bis `failed`, Abbruch per `stop()`, Retry, Übergang in die Pufferphase. Vorabprüfung und Wartezeiten sind dabei ersetzt, es wird kein Netzwerk benötigt.
- ViewModels: Overlay-Texte je Zustand, Play/Pause, Hintergrund/Vordergrund, Auto-Open und Fokus der zuletzt genutzten Kamera, Validierung in den Einstellungen

GitHub Actions (`.github/workflows/ci.yml`) baut das Projekt bei jedem Push mit Xcode auf macOS und führt die Tests auf einem Apple-TV-Simulator aus.

## Roadmap: Phase 2 – Home Assistant

1. Einstellungen um Server-URL (UserDefaults) und Long-Lived Access Token (`HomeAssistantCredentialStore` → Keychain) erweitern.
2. `HomeAssistantCameraProvider: CameraProvider` anlegen. Er liest `GET /api/states` mit `Authorization: Bearer <token>` und bildet `camera.*`-Entities ab (`id` = entity_id, `name` = friendly_name).
3. `HomeAssistantStreamURLResolver: StreamURLResolving` anlegen. Er fordert vor jedem (Re-)Connect per WebSocket-Befehl `camera/stream` eine frische HLS-URL an. Der Player ruft den Resolver bei jedem Reconnect automatisch auf.
4. In `AppDependencies.live()` die beiden Implementierungen einsetzen. Views und ViewModels bleiben unverändert.

Mögliche weitere Schritte: Vorschaubilder (`/api/camera_proxy/<entity>`), Kamerawechsel per Links/Rechts im Vollbild, Top-Shelf-Extension mit Schnappschüssen.
