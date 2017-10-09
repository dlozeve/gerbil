#!/usr/bin/env bash
set -eu

## preconditions
if [ -z "${GERBIL_SETUP+x}" ]; then
  (1>&2 echo "ERROR: Do not call this script directly.") && exit 1
fi
source "${BUILD_SCRIPT_DIR}/common.sh"

## main
feedback_low "Building gerbil stdlib"
export PATH="${GERBIL_BASE}/bin:${PATH}"
cd std && ./build-deps-gen.ss  && ./build.ss
