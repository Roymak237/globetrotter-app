#!/usr/bin/env bash
# Retires superseded release images after a deployment.
#
# Tagging each release by commit means every build leaves a distinct ~250 MB
# image behind. That is deliberate: a rollback can then re-point at a known
# good tag instead of rebuilding from restored source, which would ask the
# path that has just failed to work on a second attempt. The cost is that the
# tags accumulate, and a disk filling quietly over weeks is a far worse
# failure than one that announces itself.
#
# Three are kept. The current release, plus two earlier ones to revert to,
# which is more history than a rollback has ever needed here.
set -uo pipefail

APP_DIR="${APP_DIR:-/home/mc/project/globetrotter-app}"

# docker images lists newest first. Keeping the head and removing the tail is
# therefore date-ordered without needing to sort explicitly. The rollback tag
# is excluded: it is a moving alias onto an image that is already counted, so
# deleting it would strip a name from an image still in the retained set.
docker images --format '{{.Repository}}:{{.Tag}}' kamergo-backend \
    | grep -v ':rollback$' \
    | tail -n +4 \
    | while read -r ref; do
        # An image backing a running container cannot be removed, and should
        # not be. Failing quietly is correct: housekeeping must never decide
        # the outcome of a deployment that has already succeeded.
        docker rmi "${ref}" >/dev/null 2>&1 || true
    done

exit 0
