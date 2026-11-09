# topdecked_service

Baut die Kartendaten und den Tageskarten-Zeitplan für die Android-App **Topdecked**
aus den Bulk-Daten von [Scryfall](https://scryfall.com/docs/api/bulk-data) und
veröffentlicht sie als statische Dateien über GitHub Pages.

Die App bringt einen Grundbestand als Asset mit und lädt neuere Pakete über
`manifest.json` nach.

## Was das Build-Skript macht

1. Lädt die Scryfall-Bulk-Datei `default_cards` (in `.cache/`).
2. Filtert: nur Papier-Druckversionen; ohne Archenemy-Schemes, Planes,
   Phenomenons, Un-Karten (inkl. Unfinity und Playtest-Karten), Tokens,
   Emblems, Vanguard, Dungeons, Art-Series und Übergrößen. Conspiracy-Karten
   bleiben drin.
3. Bestimmt pro Karte (`oracle_id`) den Erstdruck: frühestes Datum,
   Promo-Sets zählen nie. Karten, die es nur als Promo gibt (z. B.
   Convention-Karten), fliegen raus.
4. Schreibt den Zeitplan fort: Alle Tage bis heute + 30 bleiben unverändert,
   neue Karten werden danach zufällig eingefügt.
5. Veröffentlicht nur, wenn sich der Inhalt geändert hat.

## Ergebnis (`site/` bzw. Branch `gh-pages`)

```
manifest.json                 Version, Dateien mit Größe und SHA-256 – die App fragt nur diese Datei ab
plan.json                     interner Zeitplan (oracle_ids), nur für das Build-Skript
data/<version>/cards.json.gz  alle Karten, nach Namen sortiert
data/<version>/sets.json      genutzte Sets mit Name und Datum
data/<version>/daily.json     {"start": "yyyy-mm-dd", "answers": [Index in cards.json, ...]}
data/<version>/version.txt
sets/<code>.svg               Set-Symbole
```

Kartenformat in `cards.json.gz`:

```json
{"i": "<oracle_id>", "n": "Lightning Bolt", "mv": 1, "mc": "{R}", "t": ["Instant"], "st": [],
 "c": ["R"], "r": "common", "s": "lea", "d": "1993-08-05", "sf": "<scryfall_id>"}
```

## Lokal ausführen

```
dart pub get
dart test
dart run bin/build.dart --site site --start 2026-11-10
dart run bin/export_assets.dart --site site --to ../topdecked/assets
```

Für Releases den Grundbestand aus den **veröffentlichten** Daten übernehmen,
damit App und Updates denselben Zeitplan haben (prüft alle Prüfsummen):

```
dart run bin/export_assets.dart --pages --to ../topdecked/assets
```

Der Starttag wird nur beim ersten Lauf gebraucht. Bis zum Release lässt er sich
mit `--reset-plan --start <datum>` ändern, danach nicht mehr.

## Automatische Updates (GitHub Actions)

Der Workflow `.github/workflows/update-data.yml` läuft montags und lässt sich
unter *Actions → Kartendaten aktualisieren → Run workflow* auch von Hand starten.

Einmalig einrichten:

1. Workflow einmal manuell starten und dabei `start` setzen. Danach gibt es den
   Branch `gh-pages`.
2. *Settings → Pages*: Source „Deploy from a branch“, Branch `gh-pages`, Ordner `/ (root)`.
3. Die Daten sind dann unter `https://melaletics.github.io/topdecked_service/manifest.json` erreichbar.

## Hinweise

Kartendaten und Bilder stammen von Scryfall. Topdecked is unofficial Fan Content
permitted under the Fan Content Policy. Not approved/endorsed by Wizards.
Portions of the materials used are property of Wizards of the Coast.
©Wizards of the Coast LLC.
