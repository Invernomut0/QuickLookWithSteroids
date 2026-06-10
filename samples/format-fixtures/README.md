# OmniPreview format fixtures

Questa cartella contiene un campione pratico di file per validare il comportamento dei renderer.

## Copertura inclusa (subito utilizzabile)

- **Source code**: `source/sample.swift`, `source/sample.py`, `source/sample.ts`
- **Text fallback senza estensione**: `source/NO_EXTENSION_TEXT`
- **Config INI-family**: `config/sample.ini`, `config/sample.cfg`, `config/sample.conf`, `config/.editorconfig`, `config/gitconfig`
- **Data/config strutturati**: `data/sample.json`, `data/sample.yaml`, `data/sample.toml`, `data/sample.sql`, `data/sample.tfstate`
- **Docs**: `docs/sample.md`
- **GIS**: `geo/sample.geojson`, `geo/sample.kml`
- **Security**: `security/sample.pem`

## Placeholder per famiglie binarie/pro

Vedi `placeholders/README.md` per i tipi che richiedono file binari reali (media, archivi, 3D, VM disk, ML).

## Uso consigliato

1. Avvia OmniPreview.
2. Trascina questi file nella finestra tester dell’app.
3. Verifica metadata/sezioni/icone.
4. Per test end-to-end più profondi, integra campioni binari reali in `placeholders/`.
