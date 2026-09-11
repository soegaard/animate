#!/bin/sh
# Run from any directory. Render the thirteen standard-library applications.
# Each video is sequential; its frames use WORKERS separate Racket processes.
# Override: RACKET=/path/to/racket WORKERS=10 sh .../render-library.sh both
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
cd "$REPO_ROOT"
RACKET=${RACKET:-racket}
WORKERS=${WORKERS:-10}
OUT=${GEOMETRY_OUTPUT:-geometry-output}

case "${1:-both}" in
  both) MODES="light dark" ;;
  light|dark) MODES=$1 ;;
  *) printf 'Usage: %s [both|light|dark]\n' "$0" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [both|light|dark]\n' "$0" >&2
  exit 2
fi

# This manifest excludes helper modules; do not glob all *.rkt files.
EXAMPLES=$(
  "$RACKET" -e '(require "geometry/examples/private/library-example-names.rkt")
                 (for-each displayln library-example-names)'
)
for mode in $MODES; do
  mkdir -p "$OUT/videos/$mode"
  for example in $EXAMPLES; do
    printf '\n=== %s / %s ===\n' "$example" "$mode"
    "$RACKET" "geometry/examples/$example.rkt" \
      --"$mode" --workers "$WORKERS" \
      --mp4 "$OUT/videos/$mode/$example.mp4" \
      "$OUT/$mode/$example"
  done
done
