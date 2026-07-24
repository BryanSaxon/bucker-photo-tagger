#!/usr/bin/env bash
# Database setup — runs once per deploy as the web service's preDeployCommand,
# so it never races with the worker. Safe on redeploys: db:migrate:primary is a
# no-op once applied, and the Solid schemas use `force: :cascade`.
set -o errexit

bundle exec rails db:migrate:primary
DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bundle exec rails db:schema:load:cache db:schema:load:queue db:schema:load:cable
