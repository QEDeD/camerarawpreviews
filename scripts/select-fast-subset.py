#!/usr/bin/env python3
import json, os, sys
manifest='tests/assets/manifest.json'
cache='tests/assets/cache'
out_path='.fast_subset'
try:
    with open(manifest) as f: data=json.load(f)
except Exception as e:
    print('Failed to read manifest:', e, file=sys.stderr); sys.exit(1)
annotated=[d for d in data if d.get('expectedTag')]
selected=[]; seen=set()
# Pick up to 3 distinct expectedTag categories
for d in annotated:
    tag=d['expectedTag']
    if tag not in seen:
        p=os.path.join(cache,d['filename'])
        if os.path.exists(p):
            selected.append(d['filename']); seen.add(tag)
    if len(seen)>=3: break
# Fallback fill to reach 3
if len(selected)<3:
    for d in data:
        if d['filename'] in selected: continue
        p=os.path.join(cache,d['filename'])
        if os.path.exists(p):
            selected.append(d['filename'])
        if len(selected)>=3: break
with open(out_path,'w') as f: f.write('\n'.join(selected))
print('Fast subset:', ', '.join(selected) if selected else '(none)')
