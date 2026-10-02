"""Write SHA-256 manifest of deliverables after all computations finish."""
from pathlib import Path
import hashlib
import pandas as pd

root = Path(__file__).resolve().parents[1]
items = []
for folder in ("code", "data", "results", "figures", "validation", "manuscript"):
    for file in sorted((root / folder).rglob("*")):
        if not file.is_file() or file.name == "deliverable_manifest.csv" or file.suffix in (".pyc",) or "__pycache__" in file.parts:
            continue
        h = hashlib.sha256()
        with file.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024*1024), b""):
                h.update(chunk)
        items.append({"relative_path":file.relative_to(root).as_posix(), "bytes":file.stat().st_size, "sha256":h.hexdigest()})
pd.DataFrame(items).to_csv(root / "validation" / "deliverable_manifest.csv", index=False)
