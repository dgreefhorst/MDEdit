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
- Een ` ```mermaid `-blok in een `.md`-bestand wordt direct als diagram getekend; klik op het diagram om de Mermaid-bron aan te passen
- Een los `.mmd`-bestand opent als diagram (Editor-weergave) met de bron in de Markdown-weergave; opslaan schrijft de ruwe Mermaid-bron terug
- Het thema (licht/donker) wordt op de diagrammen toegepast

## Exporteren
Via de werkbalk exporteer je het document naar een zelfstandige HTML-pagina of naar een echt MS Word-bestand (`.docx`, OOXML met opmaak, koppen, lijsten, tabellen, links en ingebedde afbeeldingen). De export opent het standaard macOS-opslaanpaneel. Afbeeldingen (data-URL's en URL's) worden als media in het docx-bestand opgenomen; in de app worden remote afbeeldingen via de native kant opgehaald.

Mermaid-diagrammen gaan als **vector** mee: het diagram wordt als SVG in het `.docx` opgenomen, met een PNG-fallback zodat oudere Word-versies ze ook tonen.

## Projectstructuur
- `Sources/` — Swift: app, document en WKWebView-brug
- `Web/` — de editor (HTML/JS), zonder externe afhankelijkheden
- `Info.plist` — documenttypes (Markdown en Mermaid)
- `Resources/icon.png` — 1024×1024 icoon; vervang dit voor een eigen icoon
