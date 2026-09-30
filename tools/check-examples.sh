#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <jennifer@mplx.dev>
#
# The examples are documentation that has to keep working: the docs quote them,
# so a broken example means stale docs. Running them is cheap and catches what
# the unit suites cannot - the end-to-end path through the public surface.
#
# A deck whose examples need inputs or a network host overrides this script.
# `EXAMPLES_SKIP_RUN=1` reduces it to a parse check.
#
# Usage: tools/check-examples.sh
set -euo pipefail
cd "$(dirname "$0")/.."

JENNIFER="${JENNIFER:-jennifer}"

shopt -s nullglob
examples=(examples/*.j)
shopt -u nullglob

if (( ${#examples[@]} == 0 )); then
    echo "no examples/ programs in this deck - nothing to run"
    exit 0
fi

failed=0
for example in "${examples[@]}"; do
    echo "--- ${example}"
    if [[ -n "${EXAMPLES_SKIP_RUN:-}" ]]; then
        $JENNIFER ast "$example" > /dev/null || failed=1
    else
        $JENNIFER run "$example" > /dev/null || failed=1
    fi
done

if (( failed )); then
    echo "" >&2
    echo "at least one example failed." >&2
    exit 1
fi
echo "all ${#examples[@]} examples ran"
