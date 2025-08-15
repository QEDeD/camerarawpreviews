#!/usr/bin/env bash
set -euo pipefail
MANIFEST="tests/assets/manifest.json"
CACHE_DIR="tests/assets/cache"

python3 - <<'PY'
import json, os, subprocess, sys
manifest_path='tests/assets/manifest.json'
cache_dir='tests/assets/cache'
with open(manifest_path) as f: data=json.load(f)
updated=False
# Determine exiftool command
candidates=[['vendor/exiftool/exiftool/exiftool.bin'], ['perl','vendor/exiftool/exiftool/exiftool']]
cmd=None
for c in candidates:
    if os.path.exists(c[0]):
        cmd=c
        break
if not cmd:
    print('No exiftool available (run make ensure-exiftool-bin first)');
    sys.exit(1)
for entry in data:
    if entry.get('expectedTag'): continue
    p=os.path.join(cache_dir, entry['filename'])
    if not os.path.exists(p):
        print('Skip (not cached):', entry['filename']); continue
    try:
        out=subprocess.check_output(cmd + ['-json','-preview:all','-FileType', p])
    except subprocess.CalledProcessError as e:
        print('Exiftool failed for', entry['filename'], e); continue
    info=json.loads(out)[0]
    fileType=info.get('FileType')
    priorities=['JpgFromRaw','PageImage','PreviewImage','OtherImage','ThumbnailImage']
    tag=None
    for pr in priorities:
        if pr in info:
            tag=pr; break
    if not tag:
        if fileType=='TIFF':
            tag='SourceFile'
        else:
            for pr in ['PreviewTIFF','ThumbnailTIFF']:
                if pr in info:
                    tag=pr; break
    if tag:
        entry['expectedTag']=tag
        updated=True
        print(f"Annotated {entry['filename']} -> {tag}")
    else:
        print(f"No preview tag found for {entry['filename']}")
if updated:
    with open(manifest_path,'w') as f: json.dump(data,f,indent=2)
    print('Manifest updated.')
else:
    print('No updates made.')
PY
