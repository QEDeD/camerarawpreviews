#!/usr/bin/env bash
set -euo pipefail
MANIFEST="tests/assets/manifest.json"
DEST_DIR="$(pwd)/tests/assets/cache"
mkdir -p "$DEST_DIR"
# Guard: discourage host-side asset caching; allow only inside NC container unless forced
if [ -z "${INSIDE_NC_CONTAINER:-}" ] && [ "${FORCE_HOST_FETCH:-}" != "1" ]; then
    case "$(pwd)" in
        */var/www/html/custom_apps/camerarawpreviews* ) : ;; # inside NC container mount
        * )
            echo "Refusing to cache test assets on host. Run via 'make integration' (container) or set FORCE_HOST_FETCH=1 to override." >&2
            exit 1
            ;;
    esac
fi
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

def sidecar_entry(fn):
    v=sidecar.get(fn)
    if v is None:
        return None
    if isinstance(v, str):
        # legacy format: just sha1 string
        return {'sha1': v}
    if isinstance(v, dict):
        return v
    return None

def save_sidecar():
    global updated_sidecar
    try:
        with open(sidecar_path,'w') as fh:
            json.dump(sidecar, fh, indent=2)
        print(f"Updated sidecar hashes: {sidecar_path}")
        updated_sidecar=False
    except Exception as e:
        print(f"WARNING: failed saving sidecar hashes: {e}")

for entry in manifest:
    fmt=(entry.get('format') or '').lower()
    if fmts and fmt not in fmts:
        continue
    url=entry.get('url',''); fn=entry['filename']; sha1=entry.get('sha1',''); limit=entry['size_limit']; optional=entry.get('optional', False)
    if not url:
        print(f"Skipping {fn}: missing URL in manifest")
        continue
    # encode spaces if author left unencoded
    if ' ' in url:
        parts=url.split('/')
        parts=[urllib.parse.quote(p) for p in parts]
        url='/'.join(parts)
    target=os.path.join(dest, fn)

    expect_unknown = is_unknown_sha(sha1)
    expected = None if expect_unknown else sha1
    sc = sidecar_entry(fn)
    if expect_unknown and sc and sc.get('sha1'):
        expected = sc.get('sha1')

    # If file exists, check hash and remove on mismatch to force a clean download
    timeout=float(os.environ.get('DOWNLOAD_TIMEOUT', '60'))
    if os.path.exists(target):
        with open(target,'rb') as fh:
            existing_hash=hashlib.sha1(fh.read()).hexdigest()
        if expected and existing_hash==expected:
            print(f"OK (cached): {fn}")
            continue
        # For unknown expected hashes, try a conditional HEAD to avoid unnecessary re-downloads
        if expected is None and sc:
            headers={}
            if sc.get('etag'): headers['If-None-Match']=sc['etag']
            if sc.get('last_modified'): headers['If-Modified-Since']=sc['last_modified']
            try:
                req=urllib.request.Request(url, method='HEAD', headers=headers)
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    code=r.getcode()
                    etag=r.headers.get('ETag')
                    lm=r.headers.get('Last-Modified')
                    clen=r.headers.get('Content-Length')
                if code==304:
                    print(f"OK (cached, 304): {fn}")
                    continue
                # If server didn’t send validators, fall back to re-download path
                # If it sent validators and they match our sidecar, keep cached
                if (etag and sc.get('etag')==etag) and (not lm or sc.get('last_modified')==lm):
                    print(f"OK (cached, validators match): {fn}")
                    continue
            except Exception:
                # HEAD failed; proceed to re-download
                pass
        # Mismatch or cannot confirm: remove before download
        try:
            os.remove(target)
            print(f"Removed stale file (hash mismatch/changed): {fn}")
        except FileNotFoundError:
            pass

    # Download with retries
    tries=3; backoff=1.0
    data=None; last_err=None
    for attempt in range(1, tries+1):
        try:
            req=urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                etag=r.headers.get('ETag')
                lm=r.headers.get('Last-Modified')
                tmp=target + '.tmp'
                sha=hashlib.sha1()
                total=0
                with open(tmp,'wb') as out:
                    while True:
                        chunk=r.read(1024*1024)
                        if not chunk: break
                        out.write(chunk)
                        sha.update(chunk)
                        total += len(chunk)
            data=None
            h=sha.hexdigest()
            downloaded_size=total
            # Store validators for future conditional checks
            if expect_unknown:
                if fn not in sidecar or not isinstance(sidecar.get(fn), dict):
                    sidecar[fn]={'sha1': h}
                else:
                    sidecar[fn]['sha1']=h
                if etag: sidecar[fn]['etag']=etag
                if lm: sidecar[fn]['last_modified']=lm
                sidecar[fn]['size']=downloaded_size
                updated_sidecar=True
            break
        except Exception as e:
            last_err=e
            if attempt<tries:
                time.sleep(backoff)
                backoff*=2
    if 'downloaded_size' not in locals():
        msg=f"Error downloading {fn}: {last_err}"
        if optional:
            print("Optional asset skipped - "+msg)
            continue
        else:
            print(msg, file=sys.stderr)
            errors+=1
            continue
    if downloaded_size>limit:
        # cleanup tmp
        try:
            os.remove(target + '.tmp')
        except Exception:
            pass
        msg=f"Size too large for policy: {fn} ({downloaded_size} > {limit})"
        if optional:
            print("Optional asset skipped - "+msg)
            continue
        else:
            print(msg, file=sys.stderr)
            errors+=1
            continue
    if not expect_unknown:
        if h!=expected:
            # cleanup tmp
            try:
                os.remove(target + '.tmp')
            except Exception:
                pass
            msg=f"Checksum mismatch after download: {fn}"
            if optional:
                print("Optional asset skipped - "+msg)
                continue
            else:
                print(msg, file=sys.stderr)
                errors+=1
                continue
    # Move tmp into place
    os.replace(target + '.tmp', target)
    print(f"Fetched: {fn}")

# Persist sidecar if changed
if updated_sidecar:
    save_sidecar()

if errors>0:
    print(f"Completed with {errors} error(s)", file=sys.stderr)
    sys.exit(1)
print('All assets present.')
PY
