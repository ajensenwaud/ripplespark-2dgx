#!/usr/bin/env bash
# Fetch a Hugging Face repo at a pinned revision with curl only (no host installs),
# 4 files in parallel, each LFS file checked against the Hub's sha256 before it is kept.
# Usage: fetch_source.sh <repo> <revision> <dest dir>
set -euo pipefail
REPO=$1; REV=$2; DEST=$3; JOBS=${JOBS:-4}
mkdir -p "$DEST"; cd "$DEST"
curl -sfL "https://huggingface.co/api/models/$REPO/tree/$REV?recursive=1" > .tree.json
python3 - "$REPO" "$REV" > .list <<'EOF'
import json, sys
repo, rev = sys.argv[1:3]
for x in json.load(open(".tree.json")):
    if x["type"] != "file":
        continue
    oid = x.get("lfs", {}).get("oid", "-")
    print(x["path"], oid, f"https://huggingface.co/{repo}/resolve/{rev}/{x['path']}")
EOF
fetch() {
  local path=$1 oid=$2 url=$3
  if [ -f "$path" ]; then echo "have $path"; return 0; fi
  mkdir -p "$(dirname "$path")"
  for try in 1 2 3 4 5; do
    if curl -sfL --retry 5 -C - -o "$path.part" "$url"; then break; fi
    echo "retry $try $path"; sleep 10
  done
  if [ "$oid" != "-" ]; then
    got=$(sha256sum "$path.part" | cut -d' ' -f1)
    if [ "$got" != "$oid" ]; then echo "BAD sha256 $path"; rm -f "$path.part"; return 1; fi
  fi
  mv "$path.part" "$path"; echo "ok $path"
}
export -f fetch
xargs -P "$JOBS" -L 1 bash -c 'fetch "$@"' _ < .list
n=$(wc -l < .list); have=0
while read -r p _; do [ -f "$p" ] && have=$((have + 1)); done < .list
echo "DONE $have/$n files $(date -Is)"
[ "$have" -eq "$n" ]
