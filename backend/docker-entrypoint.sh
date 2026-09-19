#!/bin/sh
# Prepares the persistent data directory before starting the app server.
#
# The data directory is a Docker volume, so it survives redeploys. That means
# image content is only copied into it the first time the volume is created.
# Without this script an updated destination catalogue would never reach a
# server that has been deployed before.
set -eu

DATA_DIR="${DATA_DIR:-/app/data}"
SEED_DIR="${SEED_DIR:-/app/seed}"

mkdir -p "$DATA_DIR"

# destinations.json is read-only reference data owned by the repository, so it
# is refreshed on every start to keep deployments in sync with the catalogue.
if [ -f "$SEED_DIR/destinations.json" ]; then
    cp "$SEED_DIR/destinations.json" "$DATA_DIR/destinations.json"
fi

# These files hold user-generated data. They are only created when absent so a
# restart or redeploy can never destroy registered accounts or saved trips.
for filename in users.json itineraries.json shares.json comments.json \
                reviews.json notifications.json submissions.json \
                chat_rooms.json chat_messages.json ratings.json \
                password_resets.json calls.json; do
    if [ ! -f "$DATA_DIR/$filename" ]; then
        printf '[]' > "$DATA_DIR/$filename"
    fi
done

# Uploaded avatars, chat attachments and voice notes live here. It sits inside
# the data volume so uploads survive a redeploy along with everything else.
mkdir -p "$DATA_DIR/media"

exec "$@"
