# Buie

Buie voert één programmeeropdracht tegelijk uit met een lokaal geïmporteerd model. Er is geen chat, account of server: het model maakt bestanden die je als zip kunt bewaren of delen.

## Gebruik

1. Installeer de app op een iPhone of iPad met iOS 16.4 of nieuwer.
2. Zet zelf een compatibel **GGUF-instructiemodel** in Bestanden en importeer het in Buie. De app kopieert het model naar de eigen opslag, uitgesloten van reservekopieën. Het model moet in het beschikbare geheugen van het apparaat passen.
3. Beschrijf de opdracht en tik op **Voer opdracht uit**. Het model draait op het apparaat; de app uploadt geen model, opdracht of resultaat.
4. Tik na voltooiing op **Exporteer zip** en kies waar je het bestand wilt bewaren. Controleer en test gegenereerde code zelf voordat je deze gebruikt.

Buie verwacht een door llama.cpp ondersteunde instructietemplate in het model en vraagt om een JSON-bestandenlijst. Niet elk GGUF-model is geschikt voor programmeren of volgt het formaat betrouwbaar. Ongeldige, onvolledige of onveilige uitvoer wordt niet geëxporteerd. De context is beperkt tot 4096 tokens voor opdracht en uitvoer samen; grote projecten kunnen niet in één opdracht passen. Inference kan veel tijd, geheugen en batterij vergen. De app kan niet garanderen dat gegenereerde code correct of volledig is.

## Bouwen

Vereist: macOS, Xcode met iOS SDK, Command Line Tools, Homebrew en XcodeGen (`brew install xcodegen`). Voer in de projectmap uit:

```sh
bash scripts/setup.sh
swift test
open Buie.xcodeproj
```

Het setupscript haalt de officiële llama.cpp b6500 XCFramework op, controleert de SHA-256 en genereert het Xcode-project. De frameworkdownload en XcodeGen zijn nodig bij een schone checkout. Kies in Xcode een eigen unieke bundle identifier en team om op een fysiek apparaat te ondertekenen.

## Codemagic

Koppel deze repository aan Codemagic en selecteer `codemagic.yaml`. De workflow **iOS simulator build** test de Swift-kern en bouwt zonder ondertekening voor de simulator. Voor **iOS signed release** wijzig je `com.example.buie` in zowel `project.yml` als `codemagic.yaml` naar je eigen geregistreerde bundle identifier en configureer je in Codemagic de Apple Developer-integratie, het distributiecertificaat en het App Store-provisioningprofiel. De releaseworkflow maakt daarna een ondertekende IPA; publicatie is niet automatisch ingesteld.
