#!/usr/bin/env bash
# Render build script — runs on every deploy for the web and worker services.
set -o errexit

bundle install
bundle exec rails tailwindcss:build
bundle exec rails assets:precompile

# App schema on the managed Postgres.
bundle exec rails db:migrate:primary

# Solid Cache/Queue/Cable tables live in the same database. Their schema files
# use `force: :cascade`, so loading them each deploy is safe (ephemeral data).
DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bundle exec rails db:schema:load:cache db:schema:load:queue db:schema:load:cable
