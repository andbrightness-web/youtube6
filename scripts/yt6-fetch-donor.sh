#!/bin/bash
# Fetch the YouTube 2.0.0 (iOS 6) app from archive.org and copy the images and
# strings listed in yt6-donor-files.txt into Opaline/YouTube6/Donor (git-ignored).
# The Xcode project syncs the Opaline folder, so they land in the app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
URL="https://archive.org/download/YouTube_2.0.0_ios_6.0/YouTube_2.0.0_ios_6.0.ipa"
SHA="451479981828254bbd376ae6030e432d3200e719e7a0c46120455ef3315898a4"
OUT="Opaline/YouTube6/Donor"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --retry 5 --retry-delay 5 -o "$TMP/donor.ipa" "$URL"
echo "$SHA  $TMP/donor.ipa" | shasum -a 256 -c -
unzip -q "$TMP/donor.ipa" -d "$TMP/x"
APP="$TMP/x/Payload/YouTube.app"

rm -rf "$OUT" && mkdir -p "$OUT"
grep -v '^#' scripts/yt6-donor-files.txt | while read -r path; do
  [ -n "$path" ] || continue
  name=$(basename "$path")
  for scale in "" "@2x"; do
    src="$APP/$path$scale.png"
    [ -f "$src" ] && cp "$src" "$OUT/yt6_$name$scale.png"
  done
  [ -f "$OUT/yt6_$name@2x.png" ] || { echo "missing $path@2x.png" >&2; exit 1; }
done

# The 2.0.0 launch image (LaunchImage-568h@2x.png: dark gray, logo) for
# YT6LaunchScreen.storyboard and the in-app splash.
cp "$APP/LaunchImage-568h@2x.png" "$OUT/yt6_launch@2x.png"

# The 2.0.0 home screen icon (Icon@2x.png, 114 px) as an app icon set for the
# iPhone sizes iOS 12 asks for; the build selects it with
# ASSETCATALOG_COMPILER_APPICON_NAME=YT6AppIcon. Needs macOS sips.
if command -v sips >/dev/null; then
  SET="$OUT/YT6Icons.xcassets/YT6AppIcon.appiconset"
  mkdir -p "$SET"
  printf '{"info":{"version":1,"author":"xcode"}}' > "$OUT/YT6Icons.xcassets/Contents.json"
  images=""
  for spec in 20:2 20:3 29:2 29:3 40:2 40:3 60:2 60:3; do
    pt=${spec%:*}; sc=${spec#*:}; px=$((pt * sc)); file="icon-$px.png"
    sips -z "$px" "$px" "$APP/Icon@2x.png" --out "$SET/$file" >/dev/null
    images="$images{\"idiom\":\"iphone\",\"size\":\"${pt}x${pt}\",\"scale\":\"${sc}x\",\"filename\":\"$file\"},"
  done
  printf '{"images":[%s],"info":{"version":1,"author":"xcode"}}' "${images%,}" > "$SET/Contents.json"
fi

# Guide and section titles as shipped in 2.0.0, in every language it had.
python3 - "$APP" "$OUT/yt6_strings.json" <<'PY'
import json, os, plistlib, sys
app, out = sys.argv[1], sys.argv[2]
result = {}
for entry in sorted(os.listdir(app)):
    if not entry.endswith(".lproj"):
        continue
    table = {}
    for name in ("UILib.strings", "Localizable.strings"):
        path = os.path.join(app, entry, name)
        if os.path.exists(path):
            with open(path, "rb") as f:
                table.update(plistlib.load(f))
    if table:
        result[entry[:-6]] = table
json.dump(result, open(out, "w"), ensure_ascii=False)
PY
echo "donor: $(ls "$OUT" | wc -l | tr -d ' ') files in $OUT"
