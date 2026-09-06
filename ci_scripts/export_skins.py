"""Export only runtime artwork/config from the Edu source, never account data."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile

source, output = map(Path, sys.argv[1:])
config = json.loads((source / "skins.json").read_text())
runtime = {key: config[key] for key in ("tiers", "eras")}
files = {"skins.json": json.dumps(runtime, ensure_ascii=False).encode()}
for era in ("slum", "cottage", "garden", "manor", "golden"):
    data = (source / era / "bg.jpg").read_bytes()
    if not data.startswith(b"\xff\xd8\xff"):
        raise ValueError(f"Invalid JPEG: {era}")
    files[f"{era}/bg.jpg"] = data
with tarfile.open(output, "w:gz") as archive:
    for name, data in files.items():
        entry = tarfile.TarInfo(name)
        entry.size = len(data)
        entry.mode = 0o644
        archive.addfile(entry, io.BytesIO(data))
print(hashlib.sha256(output.read_bytes()).hexdigest())
