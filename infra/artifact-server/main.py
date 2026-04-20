#!/usr/bin/env python3
"""
Simple artifact server: upload tar/zip files, serve them for download.
Stores files in a single directory; supports concurrent uploads.
Writes a server-side MD5 digest file next to each artifact: {name}.md5 (hex + newline).
Hidden metadata file: .{name}.meta with key=value format (retain_days, uploaded timestamp).
Built-in daily cleanup at 03:00 UTC.
"""
from datetime import datetime, timedelta
from contextlib import asynccontextmanager
import hashlib
from pathlib import Path
import os
import re
import asyncio
import logging

from fastapi import FastAPI, File, Header, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse

log = logging.getLogger("artifact-server")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

ARTIFACTS_DIR = Path(__file__).resolve().parent / "artifacts"
ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
SAFE_NAME_RE = re.compile(r"^[a-zA-Z0-9_.-]+$")
CLEANUP_HOUR = 3
CLEANUP_INTERVAL_HOURS = 24


def safe_name(name: str) -> str:
    base = os.path.basename(name).strip()
    if not base or not SAFE_NAME_RE.match(base):
        raise HTTPException(status_code=400, detail="Invalid artifact name")
    return base


def do_cleanup() -> list[str]:
    removed = []
    now = datetime.utcnow()
    for p in ARTIFACTS_DIR.iterdir():
        if not p.is_file() or p.name.startswith('.'):
            continue
        meta_path = ARTIFACTS_DIR / f".{p.name}.meta"
        if not meta_path.exists():
            continue
        meta = {}
        for line in meta_path.read_text(encoding="utf-8").strip().splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                meta[k] = v
        try:
            uploaded = datetime.fromisoformat(meta.get('uploaded', ''))
            retain_days = int(meta.get('retain_days', 2))
            if now - uploaded > timedelta(days=retain_days):
                p.unlink(missing_ok=True)
                meta_path.unlink(missing_ok=True)
                (ARTIFACTS_DIR / f"{p.name}.md5").unlink(missing_ok=True)
                removed.append(p.name)
        except (ValueError, OSError) as e:
            log.warning(f"cleanup skip {p.name}: {e}")
    return removed


async def cleanup_task():
    while True:
        now = datetime.utcnow()
        target = now.replace(hour=CLEANUP_HOUR, minute=0, second=0, microsecond=0)
        if now.hour >= CLEANUP_HOUR:
            target += timedelta(days=1)
        wait_seconds = (target - now).total_seconds()
        log.info(f"next cleanup at {target.isoformat()} (wait {wait_seconds:.0f}s)")
        await asyncio.sleep(wait_seconds)
        try:
            removed = do_cleanup()
            log.info(f"cleanup removed {len(removed)} artifacts: {removed}")
        except Exception as e:
            log.error(f"cleanup failed: {e}")
        await asyncio.sleep(CLEANUP_INTERVAL_HOURS * 3600)


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(cleanup_task())
    log.info("started daily cleanup background task")
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass
    log.info("stopped cleanup task")


app = FastAPI(title="Artifact Server", version="1.2", lifespan=lifespan)


@app.post("/upload")
async def upload_artifact(
    file: UploadFile = File(...),
    retain_days: int = Query(default=2, ge=1, le=90, description="Days to retain artifact")
):
    artifact_name = safe_name(file.filename or "artifact")
    dest = ARTIFACTS_DIR / artifact_name
    if dest.is_file():
        raise HTTPException(
            status_code=409,
            detail=f"Artifact already exists: {artifact_name}. Re-upload is not allowed.",
        )
    md5_path = ARTIFACTS_DIR / f"{artifact_name}.md5"
    meta_path = ARTIFACTS_DIR / f".{artifact_name}.meta"
    try:
        digest = hashlib.md5()
        with open(dest, "wb") as f:
            while chunk := await file.read(1024 * 1024):
                digest.update(chunk)
                f.write(chunk)
        md5_path.write_text(digest.hexdigest() + "\n", encoding="ascii")
        uploaded_ts = datetime.utcnow().isoformat()
        meta_path.write_text(f"retain_days={retain_days}\nuploaded={uploaded_ts}\n", encoding="utf-8")
    except OSError as e:
        dest.unlink(missing_ok=True)
        md5_path.unlink(missing_ok=True)
        meta_path.unlink(missing_ok=True)
        raise HTTPException(status_code=500, detail=str(e))
    return JSONResponse({"ok": True, "name": artifact_name, "retain_days": retain_days})


def _artifacts_listing_html() -> str:
    """Build http.server-style directory index with links and create time."""
    entries = [(p.name, datetime.fromtimestamp(p.stat().st_mtime)) for p in ARTIFACTS_DIR.iterdir() if p.is_file()]
    entries.sort(key=lambda e: e[0])
    rows = "".join(
        f'<li><a href="/artifacts/{name}">{name}</a> — {mtime.strftime("%Y-%m-%d %H:%M:%S")}</li>'
        for name, mtime in entries
    )
    return f"""<!DOCTYPE html>
<html>
<head><title>Artifacts</title></head>
<body>
<h1>Artifacts</h1>
<ul>
{rows or "<li>(no files)</li>"}
</ul>
</body>
</html>"""


def _artifacts_list() -> list[str]:
    """Return sorted list of artifact filenames."""
    return sorted(p.name for p in ARTIFACTS_DIR.iterdir() if p.is_file())


@app.get("/artifacts/latest")
async def latest_artifact(pattern: str = Query(..., description="Regex to match artifact names")):
    """Redirect to the latest (by mtime) artifact whose name matches the regex."""
    try:
        rx = re.compile(pattern)
    except re.error as e:
        raise HTTPException(status_code=400, detail=f"Invalid regex: {e}")
    matches = []
    for p in ARTIFACTS_DIR.iterdir():
        if p.is_file() and not p.name.endswith(".md5") and rx.search(p.name):
            matches.append((p.name, p.stat().st_mtime))
    if not matches:
        raise HTTPException(status_code=404, detail="No artifact matching pattern")
    matches.sort(key=lambda x: -x[1])
    latest_name = matches[0][0]
    return RedirectResponse(url=f"/artifacts/{latest_name}", status_code=302)


@app.get("/artifacts", response_class=HTMLResponse)
@app.get("/artifacts/", response_class=HTMLResponse)
async def list_artifacts(accept: str | None = Header(None)):
    """Directory listing with links (HTML) or JSON list when Accept: application/json."""
    if accept and "application/json" in accept:
        return JSONResponse({"artifacts": _artifacts_list()})
    return _artifacts_listing_html()


@app.get("/artifacts/{name:path}")
async def get_artifact(name: str):
    name = (name or "").rstrip("/")
    if not name:
        return HTMLResponse(_artifacts_listing_html())
    safe = safe_name(name)
    path = ARTIFACTS_DIR / safe
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Artifact not found")
    return FileResponse(path, filename=safe, media_type="application/octet-stream")


@app.get("/cleanup")
async def cleanup_expired():
    removed = do_cleanup()
    return JSONResponse({"removed": removed, "count": len(removed)})


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8765")))
