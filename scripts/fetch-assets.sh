#!/usr/bin/env bash
set -euo pipefail
MANIFEST="tests/assets/manifest.json"
DEST_DIR="$(pwd)/tests/assets/cache"
mkdir -p "$DEST_DIR"
python3 - <<'PY'
import json, os, sys, hashlib, urllib.request, urllib.parse, time
manifest=json.load(open('tests/assets/manifest.json'))
dest=os.path.join('tests','assets','cache')
os.makedirs(dest, exist_ok=True)
errors=0
fmts_env=os.environ.get('FORMATS','')
fmts=set([s.strip().lower() for s in fmts_env.split(',') if s.strip()])
for entry in manifest:
    fmt=(entry.get('format') or '').lower()
    if fmts and fmt not in fmts:
        continue
    url=entry['url']; fn=entry['filename']; sha1=entry['sha1']; limit=entry['size_limit']; optional=entry.get('optional', False)
    # encode spaces if author left unencoded
    if ' ' in url:
        parts=url.split('/')
        parts=[urllib.parse.quote(p) for p in parts]
        url='/'.join(parts)
    target=os.path.join(dest, fn)
    if os.path.exists(target):
        h=hashlib.sha1(open(target,'rb').read()).hexdigest()
        if h==sha1:
            print(f"OK (cached): {fn}")
            continue
        else:
            print(f"Hash mismatch, re-downloading: {fn}")
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
    if h!=sha1:
        msg=f"Checksum mismatch after download: {fn}"
        if optional:
            print("Optional asset skipped - "+msg)
            continue
        else:
            print(msg, file=sys.stderr)
            errors+=1
            continue
    open(target,'wb').write(data)
    print(f"Fetched: {fn}")
if errors>0:
    print(f"Completed with {errors} error(s)", file=sys.stderr)
    sys.exit(1)
print('All assets present.')
PY
