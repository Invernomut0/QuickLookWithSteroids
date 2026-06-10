# Binary/Pro placeholder fixtures

Questa cartella contiene placeholder per famiglie formato che richiedono file binari reali
(o campioni più pesanti) per test manuali completi.

Esempi da sostituire con file reali:

- `sample.mp4` / `sample.wav` (Media)
- `sample.png` / `sample.jpg` / `sample.heic` (Image)
- `sample.zip` / `sample.tar` / `sample.gz` (Archive)
- `sample.sqlite` (SQLite)
- `sample.glb` / `sample.stl` (3D)
- `sample.qcow2` / `sample.vmdk` (Disk image)
- `sample.gguf` / `sample.safetensors` / `sample.onnx` / `sample.npy` (ML)

Per generare fixture binari minimali e validi in modo automatico, puoi riusare gli helper presenti in `Core/Tests/OmniPreviewCoreTests/FixtureBuilder.swift` nei test.
