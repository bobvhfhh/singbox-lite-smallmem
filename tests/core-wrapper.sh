#!/usr/bin/env bash
set -e
core="${0##*/}"
if [[ "$1" == check || " $* " == *' -test '* ]]; then
    for pid in $(pgrep -x "$core"); do
        if [[ "$pid" != "$$" && -e "/proc/$pid/exe" ]]; then
            echo "ERROR: validation overlaps running $core" >&2
            exit 91
        fi
    done
    echo "$core check" >> /results/core-events
fi
exec -a "$0" "/opt/cores/$core" "$@"
