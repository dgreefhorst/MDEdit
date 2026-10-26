# MDEdit — native macOS-app (SwiftUI)

Document-gebaseerde Mac-app: SwiftUI `DocumentGroup` + `FileDocument` voor het bestandsbeheer, en een WKWebView met de WYSIWYG-editor voor het bewerken.

## Bouwen
Vereist macOS 13+ en de Xcode Command Line Tools (`xcode-select --install`).

    ./build.sh
    open "build/MDEdit.app"

Het script bouwt een universal app (Apple Silicon + Intel), maakt het icoon en ondertekent de app ad-hoc.

## Native functies (van macOS zelf)
- Bestand-menu: Nieuw, Openen, Recent geopend, Opslaan, Duplicate, Hernoemen, Verplaatsen, Terugzetten naar versie
- Automatisch opslaan in het bestand zelf, met versiegeschiedenis
- Meerdere vensters en tabbladen, "Open met…" in Finder, `.md` en `.mmd` worden aan deze app gekoppeld
- Titelbalk met bestandsnaam en bewerkt-markering, Spotlight/QuickLook blijven werken
- Lichte/donkere weergave volgt het systeem; Weergave-menu met Cmd+Option+1/2/3
- Werkt volledig offline (marked, turndown en mermaid zijn meegeleverd)

## Diagrammen (Mermaid)
- Een ` ```mermaid `-blok in een `.md`-bestand wordt direct als diagram getekend; klik op het diagram om het te vergroten (zoomen met de knoppen of knijpen, slepen om te verschuiven) en gebruik **Bron bewerken** of Option-klik om de Mermaid-bron aan te passen
- Een los `.mmd`-bestand opent als diagram (Editor-weergave) met de bron in de Markdown-weergave; opslaan schrijft de ruwe Mermaid-bron terug
- Het thema (licht/donker) wordt op de diagrammen toegepast

## Exporteren
Via de werkbalk exporteer je het document naar een zelfstandige HTML-pagina of naar een echt MS Word-bestand (`.docx`, OOXML met opmaak, koppen, lijsten, tabellen, links en ingebedde afbeeldingen). De export opent het standaard macOS-opslaanpaneel. Afbeeldingen (data-URL's en URL's) worden als media in het docx-bestand opgenomen; in de app worden remote afbeeldingen via de native kant opgehaald.

Mermaid-diagrammen gaan in het `.docx` als **afbeelding** mee (op drievoudige resolutie). Word's eigen SVG-weergave geeft mermaid's uitvoer niet goed weer — ook niet als je de SVG handmatig invoegt — dus een SVG in het docx levert hokken zonder tekst of ontbrekende randen op.

Open je een los `.mmd`-bestand, dan verschijnen er twee extra knoppen:
- **SVG** — het diagram zelf als vector-SVG, op het formaat van het diagram, met echte tekst en zonder filters die tekenprogramma's als Inkscape en Illustrator niet ondersteunen.
- **PDF** — het diagram als vector-PDF op het formaat van het diagram. Dit is de route voor MS Word: de PDF bestaat uit vectoren en tekst (geen plaatje) en is in Word in te voegen.

## Projectstructuur
- `Sources/` — Swift: app, document en WKWebView-brug
- `Web/` — de editor (HTML/JS), zonder externe afhankelijkheden
- `Info.plist` — documenttypes (Markdown en Mermaid)
- `Resources/icon.png` — 1024×1024 icoon; vervang dit voor een eigen icoon
