# Icons

PWA-ikonene som manifest.json refererer:

| Fil                          | Størrelse | Bruk                                       |
| ---------------------------- | --------- | ------------------------------------------ |
| `icon.svg`                   | vektor    | Primær (Chrome/Edge bruker den hvis mulig) |
| `icon-192.png`               | 192×192   | Android-installasjon, andre fallbacks      |
| `icon-512.png`               | 512×512   | Splash-screen, high-density android        |
| `icon-192-maskable.png`      | 192×192   | Adaptive icons (Android, safe-area-pad)    |
| `icon-512-maskable.png`      | 512×512   | Adaptive icons high-res                    |
| `apple-touch-icon.png`       | 180×180   | iOS "Legg til på startskjerm"              |

## Generere PNG-ene

Vi har ingen image-encoder-pakke i prosjektet (sharp/jimp er ikke installert).
Åpne `icons/generate.html` i en nettleser → klikk hver "Last ned"-knapp →
flytt PNG-ene hit i `icons/`-mappa. Engangsjobb.

## Erstatte med ekte logo

Når Markus har en faktisk logo-fil (Figma/Illustrator), kan PNG-ene erstattes
direkte. Hold dimensjonene som tabellen sier. SVG-en kan også oppdateres,
manifest.json refererer både SVG og PNG, så ulike enheter får best mulig
versjon.

## Safe-area for maskable ikoner

Android-kommunenes "adaptive icons" kan klippe ikonet til sirkel, droplet
eller squircle. Maskable-variantene må derfor ha minst 10% padding rundt
det viktige innholdet. `generate.html` legger inn dette automatisk.
