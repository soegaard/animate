#!/usr/bin/env sh

# CI needs svg >= 0.3, but a fresh Racket installation can resolve an older
# catalog entry (or have an older user-scoped copy).  Install the maintained
# source explicitly before installing Animate, while retaining the catalog
# report as a non-fatal diagnostic for the packaging issue.
set -eu

racket --version
raco pkg catalog-show svg || true
raco pkg remove --auto --batch --scope user svg || true
raco pkg install --auto --batch --scope user --name svg \
  https://github.com/soegaard/svg.git
raco pkg show svg
