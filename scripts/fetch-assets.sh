#!/usr/bin/env bash
set -euo pipefail
MANIFEST="tests/assets/manifest.json"
DEST_DIR="$(pwd)/tests/assets/cache"
mkdir -p "$DEST_DIR"
python3 - <<'PY'
import json, os, sys, hashlib, urllib.request, urllib.parse
manifest=json.load(open('tests/assets/manifest.json'))
dest=os.path.join('tests','assets','cache')
os.makedirs(dest, exist_ok=True)
errors=0
for entry in manifest:
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
    try:
        with urllib.request.urlopen(url) as r:
            data=r.read()
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
    except Exception as e:
        msg=f"Error downloading {fn}: {e}"
        if optional:
            print("Optional asset skipped - "+msg)
            continue
        else:
            print(msg, file=sys.stderr)
            errors+=1
if errors:
    print(f"Completed with {errors} error(s)", file=sys.stderr)
    sys.exit(1)
print('All assets present.')
PY
