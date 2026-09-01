# Portretter

Bildene som vises i behandlerkortene i bestillingsflyten.

## Hva som skal ligge her

    markus.png      Markus Westengen
    terapeut.png    «Markus' terapeuter» (gruppebildet)

## Krav

- Kvadratisk. 192×192 px eller større; kortet viser dem på 48×48,
  og dobbelt opp gir et skarpt bilde på skjermer med høy tetthet.
- Motivet sentrert, med luft rundt hodet. Kortet klipper bildet
  rundt, så et tett utsnitt mister toppen av hodet.
- PNG eller JPG. Under 200 kB hver.

## Slik slås de på

Filene vises ikke automatisk. `PORTRETTER` i
`shared/booking-flow.js` er tom, og da spør ingen etter en fil som
ikke finnes — det ville gitt en 404 i konsollen på hver eneste
visning. Legg inn filene her, og fyll ut oppføringene:

    var PORTRETTER = {
      markus:   'assets/avatars/markus.png',
      terapeut: 'assets/avatars/terapeut.png'
    };

Uten oppføring viser kortet initialene (MW, MT) i den blå boksen.
Det gjør det også hvis en fil er ført opp men mangler.

`placeholder.svg` er ikke i bruk i koden. Den ligger her som mal for
format og utsnitt.
