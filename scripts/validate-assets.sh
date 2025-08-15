#!/usr/bin/env bash
set -euo pipefail
MANIFEST="tests/assets/manifest.json"
CACHE_DIR="tests/assets/cache"
THRESHOLD_WARN=350000000   # 350 MB
THRESHOLD_HARD=400000000   # 400 MB
ENFORCE_COVERAGE=${ENFORCE_COVERAGE:-0}  # set to 1 to make <70% a hard failure

python3 - <<'PY'
import json, os, hashlib, sys
manifest_path='tests/assets/manifest.json'
cache_dir='tests/assets/cache'
with open(manifest_path) as f:
    data=json.load(f)
missing=[]; wrong=[]; total_size=0; annotated=0
optional_missing=[]
required_categories={'JpgFromRaw','PreviewImage','OtherImage','ThumbnailImage','SourceFile'}
cat_seen=set()
for entry in data:
    fn=entry['filename']; sha1=entry['sha1']; exp=entry.get('expectedTag')
    p=os.path.join(cache_dir, fn)
    if not os.path.exists(p):
        if entry.get('optional'):
            optional_missing.append(fn)
        else:
            missing.append(fn)
        continue
    with open(p,'rb') as fh: h=hashlib.sha1(fh.read()).hexdigest()
    if h!=sha1: wrong.append(fn)
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
