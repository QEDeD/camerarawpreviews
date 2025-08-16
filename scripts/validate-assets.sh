#!/usr/bin/env bash
set -euo pipefail
MANIFEST="tests/assets/manifest.json"
CACHE_DIR="tests/assets/cache"
THRESHOLD_WARN=2500000000   # 2.5 GB
THRESHOLD_HARD=3000000000   # 3.0 GB
ENFORCE_COVERAGE=${ENFORCE_COVERAGE:-0}  # set to 1 to make <70% a hard failure

python3 - <<'PY'
import json, os, hashlib, sys
manifest_path='tests/assets/manifest.json'
cache_dir='tests/assets/cache'
sidecar_path=os.path.join(cache_dir,'.sha1.json')
with open(manifest_path) as f:
    data=json.load(f)
sidecar={}
if os.path.exists(sidecar_path):
    try:
        sidecar=json.load(open(sidecar_path)) or {}
    except Exception:
        sidecar={}

missing=[]; wrong=[]; total_size=0; annotated=0
optional_missing=[]
required_categories={'JpgFromRaw','PreviewImage','OtherImage','ThumbnailImage','SourceFile'}
cat_seen=set()

def is_unknown_sha(sha):
    if not sha: return True
    s=str(sha).lower()
    return s in ('auto','unknown','0','00','000','0000') or (len(s)==40 and set(s)=={'0'})

for entry in data:
    fn=entry['filename']; sha1=entry.get('sha1',''); exp=entry.get('expectedTag')
    p=os.path.join(cache_dir, fn)
    if not os.path.exists(p):
        if entry.get('optional'):
            optional_missing.append(fn)
        else:
            missing.append(fn)
        continue
    with open(p,'rb') as fh: h=hashlib.sha1(fh.read()).hexdigest()
    expected = None if is_unknown_sha(sha1) else sha1
    if expected is None:
        # Accept sidecar recorded hash when manifest sha is unknown
        sc = sidecar.get(fn)
        if sc and h!=sc:
            wrong.append(fn)
        elif sc is None:
            # Sidecar missing; record current to avoid failing validation spuriously
            sidecar[fn]=h
            try:
                with open(sidecar_path,'w') as fh2:
                    json.dump(sidecar, fh2, indent=2)
            except Exception:
                pass
    else:
        if h!=expected: wrong.append(fn)
    total_size+=os.path.getsize(p)
    if exp: cat_seen.add(exp); annotated+=1
ratio= annotated/len(data) if data else 0
print(f"Assets listed: {len(data)}; present: {len(data)-len(missing)-len(optional_missing)}; annotated: {annotated} ({ratio:.0%})")
print(f"Total size bytes: {total_size}")
if missing: print('Missing files:', ', '.join(missing))
if optional_missing: print('Missing optional files (ignored for failure):', ', '.join(optional_missing))
if wrong: print('Checksum mismatches:', ', '.join(wrong))
if ratio >= 0.7:
    missing_cats=required_categories - cat_seen
    if missing_cats:
        print('WARNING: Missing tag categories (expectedTag): ' + ', '.join(sorted(missing_cats)))
status=0
if missing or wrong:
    status=1
if ratio < 0.7:
    if ENFORCE_COVERAGE == '1':
        print('ERROR: Annotation coverage below required 70%.'); status=1
    else:
        print('WARNING: Annotation coverage below 70% (informational; set ENFORCE_COVERAGE=1 to enforce).')
open('.asset_size','w').write(str(total_size))
sys.exit(status)
PY

SIZE=$(cat .asset_size)
if [ "$SIZE" -gt $THRESHOLD_HARD ]; then
    echo "ERROR: Asset size $SIZE exceeds hard limit $THRESHOLD_HARD" >&2
  exit 1
elif [ "$SIZE" -gt $THRESHOLD_WARN ]; then
    echo "WARNING: Asset size $SIZE exceeds warn threshold $THRESHOLD_WARN" >&2
fi

echo "Asset validation complete."
