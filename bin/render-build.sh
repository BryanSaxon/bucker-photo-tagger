#!/usr/bin/env bash
# Render build script (web + worker). Assets only — no database work, so the two
# services never race on the database. Schema setup happens once in the web
# service's preDeployCommand (see bin/render-migrate.sh).
set -o errexit

bundle install
bundle exec rails tailwindcss:build
bundle exec rails assets:precompile
