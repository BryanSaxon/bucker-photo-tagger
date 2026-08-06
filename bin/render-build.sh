#!/usr/bin/env bash
# Render build script for the NATIVE Ruby runtime.
#
# Currently unused: render.yaml builds both services from the Dockerfile so the
# image can carry libheif/libde265 for HEIC decoding, which the native runtime
# can't install. Kept so reverting render.yaml to `runtime: ruby` is a one-line
# change. Assets only — schema setup happens in bin/render-migrate.sh.
set -o errexit

bundle install
bundle exec rails tailwindcss:build
bundle exec rails assets:precompile
