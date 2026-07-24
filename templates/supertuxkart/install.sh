#!/bin/sh
# Seed SuperTuxKart server data.

set -eu

mkdir -p /data/supertuxkart
chown -R svc:svc /data/supertuxkart 2>/dev/null || true
echo "supertuxkart data ready"
