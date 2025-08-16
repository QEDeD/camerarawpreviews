#!/usr/bin/env bash
set -euo pipefail
MANIFEST="tests/assets/manifest.json"
DEST_DIR="$(pwd)/tests/assets/cache"
mkdir -p "$DEST_DIR"
python3 - <<'PY'
import json, os, sys, hashlib, urllib.request, urllib.parse, time

# Locations
manifest_path='tests/assets/manifest.json'
dest=os.path.join('tests','assets','cache')
os.makedirs(dest, exist_ok=True)
sidecar_path=os.path.join(dest, '.sha1.json')

# Load manifest and sidecar hashes (for entries with unknown sha1)
manifest=json.load(open(manifest_path))
sidecar={}
if os.path.exists(sidecar_path):
    try:
        sidecar=json.load(open(sidecar_path)) or {}
    except Exception:
        sidecar={}

errors=0
updated_sidecar=False

# Env filter for formats
fmts_env=os.environ.get('FORMATS','')
fmts=set([s.strip().lower() for s in fmts_env.split(',') if s.strip()])

def is_unknown_sha(sha):
    if not sha: return True
    s=str(sha).lower()
    return s in ('auto','unknown','0','00','000','0000') or (len(s)==40 and set(s)=={'0'})

for entry in manifest:
    fmt=(entry.get('format') or '').lower()
    if fmts and fmt not in fmts:
        continue
    url=entry['url']; fn=entry['filename']; sha1=entry.get('sha1',''); limit=entry['size_limit']; optional=entry.get('optional', False)
    # encode spaces if author left unencoded
    if ' ' in url:
        parts=url.split('/')
        parts=[urllib.parse.quote(p) for p in parts]
        url='/'.join(parts)
    target=os.path.join(dest, fn)

    expect_unknown = is_unknown_sha(sha1)
    expected = None if expect_unknown else sha1
    if expect_unknown:
        expected = sidecar.get(fn)

    # If file exists, check hash and remove on mismatch to force a clean download
    if os.path.exists(target):
        with open(target,'rb') as fh:
            existing_hash=hashlib.sha1(fh.read()).hexdigest()
        if expected and existing_hash==expected:
            print(f"OK (cached): {fn}")
            continue
        if expected is None and fn in sidecar:
            # Unknown in manifest, but we have a recorded sidecar hash; enforce consistency
            if existing_hash==sidecar[fn]:
                print(f"OK (cached, sidecar): {fn}")
                continue
        # Mismatch or no expectation: remove before download
        try:
            os.remove(target)
            print(f"Removed stale file (hash mismatch): {fn}")
        except FileNotFoundError:
            pass

    # Download with retries
    tries=3; backoff=1.0
    data=None; last_err=None
    for attempt in range(1, tries+1):
        try:
            with urllib.request.urlopen(url) as r:
                data=r.read()
            break
        except Exception as e:
            last_err=e
            if attempt<tries:
                time.sleep(backoff)
                backoff*=2
    if data is None:
        msg=f"Error downloading {fn}: {last_err}"
        if optional:
            print("Optional asset skipped - "+msg)
            continue
        else:
            print(msg, file=sys.stderr)
            errors+=1
            continue
    if len(data)>limit:
        msg=f"Size too large for policy: {fn} ({len(data)} > {limit})"
        if optional:
            print("Optional asset skipped - "+msg)
            continue
        else:
            print(msg, file=sys.stderr)
            errors+=1
            continue

    h=hashlib.sha1(data).hexdigest()
    if not expect_unknown:
        if h!=expected:
            msg=f"Checksum mismatch after download: {fn}"
            if optional:
                print("Optional asset skipped - "+msg)
                continue
            else:
                print(msg, file=sys.stderr)
                errors+=1
                continue
    else:
        # Record discovered hash for unknown entries into sidecar
        if sidecar.get(fn)!=h:
            sidecar[fn]=h
            updated_sidecar=True

    with open(target,'wb') as out:
        out.write(data)
    print(f"Fetched: {fn}")

# Persist sidecar if changed
if updated_sidecar:
    try:
        with open(sidecar_path,'w') as fh:
            json.dump(sidecar, fh, indent=2)
        print(f"Updated sidecar hashes: {sidecar_path}")
    except Exception as e:
        print(f"WARNING: failed saving sidecar hashes: {e}")

if errors>0:
    print(f"Completed with {errors} error(s)", file=sys.stderr)
    sys.exit(1)
print('All assets present.')
PY
