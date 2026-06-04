#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOTS="$ROOT/snapshots/gas"
DOC="$ROOT/docs/gas-benchmarks.md"
Y_MAX=1000000000

mkdir -p "$SNAPSHOTS"

FOUNDRY_PROFILE=gas forge snapshot --isolate -vv

charts="$(mktemp)"
trap 'rm -f "$charts"' EXIT

for file in "$SNAPSHOTS"/*.json; do
  stem="$(basename "$file" .json)"
  title="$(echo "${stem%_nonceDepth}" | sed -E 's/([a-z0-9])([A-Z])/\1 \2/g;s/^./\U&/')"
  x_axis="$(jq -r '[keys[]|tonumber]|sort|map(tostring)|"[\(join(", "))]"' "$file")"
  line="$(jq -r 'to_entries|sort_by(.key|tonumber)|map(.value)|"[\(join(", "))]"' "$file")"

  cat >>"$charts" <<EOF
\`\`\`mermaid
xychart
    title "$title"
    x-axis "Nonce" $x_axis
    y-axis "Gas Cost" 0 --> $Y_MAX
    line $line
\`\`\`

EOF
done

awk -v begin='<!-- Begin: generated -->' -v end='<!-- End: generated -->' -v charts="$charts" '
  $0 == begin { print; while ((getline line < charts) > 0) print line; close(charts); skip = 1; next }
  skip && $0 == end { skip = 0; print; next }
  !skip { print }
' "$DOC" >"${DOC}.tmp"

mv "${DOC}.tmp" "$DOC"
