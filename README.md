# Photo Tagger

Internal tool for a home builder to categorize marketing/example photos. Each
photo is tagged with a **community**, a **floorplan**, and one or more **SKUs**
visible in the image (optionally pinned to a location on the photo). The tagged
photos are later shown to buyers as examples of what their selections look like.

This is a focused, one-off tool intended to be ported into the main production
app later, so business logic lives in service objects and the code is kept
deliberately simple.

## Stack

- **Ruby 4.0**, **Rails 8.1**
- **PostgreSQL**
- **Tailwind CSS v4** (`tailwindcss-rails`, propshaft, importmap) — design language
  matched to the `buyer_companion_demo` app (Sora + IBM Plex Mono, gold `#F5A623`
  accent)
- **Solid Queue / Solid Cache / Solid Cable**, all database-backed (development
  mirrors production with dedicated `cache`/`queue`/`cable` databases)
- **Active Storage** for photo uploads
- Rails' built-in authentication generator

## Getting started

```bash
bin/setup                 # installs gems, prepares the databases
bin/rails db:seed         # seed login user, communities, floorplans, sample SKUs
bin/dev                   # boots web + tailwind watcher + Solid Queue worker
```

Then sign in at http://localhost:3000 with the seed user:

- **Email:** `accounts@bryansaxon.com`
- **Password:** `password`

Run the test suite with `bin/rails test`.

## Features

1. **Upload & index** — drag-and-drop multi-photo upload. The index lists photos,
   filtered to those needing processing by default, with a toggle for completed
   photos and a name search.
2. **Processing screen** — the photo fills ~75% of the width on the left; the
   right panel has community/floorplan selects and a live SKU multi-select with
   search. Saving marks the photo complete and records who processed it.
   Completed photos remain editable.
3. **SKU location tagging (bonus)** — after adding a SKU you can pin where it
   appears in the photo; normalized (0–1) coordinates are stored on the
   `photo_skus` join for later use in room renderings.
4. **SKU sync** — the SKU Library page has a "Refresh SKUs from API" button that
   enqueues a Solid Queue background job to sync the catalog. It is manual only
   (never scheduled) and the page shows the latest sync status.

## NewStart API configuration

The SKU catalog is synced from the NewStart `product_library` endpoint (see
`docs/newstart-api-field-guide.html`). The API is read-only, unpaginated, and
authenticates with a Rails-style structured token header carrying both a token
and an email. Configure via environment variables (or Rails credentials under
`newstart`):

```bash
NEWSTART_API_BASE_URL=https://api.example.com
NEWSTART_API_TOKEN=your-token
NEWSTART_API_EMAIL=your-account@example.com
```

Until these are set, the sync job records a clear "not configured" failure and
the seeded sample SKUs stand in for the real catalog. Notable field mappings
(the source catalog has **no** name/manufacturer/price/image-URL fields):

| Sku column          | API `Product` field   |
|---------------------|-----------------------|
| `product_code`      | `product_code` (key)  |
| `short_description` | `short_description`   |
| `category_code`     | `category_code`       |
| `subcategory_code`  | `subcategory_code`    |
| `attribute1_desc`   | `attribute1_desc`     |
| `attribute1`        | `attribute1` (CSV)    |
| `image_flag`        | `image` (sentinel)    |
| `source_modified_at`| `lastmoddatetime`     |

## Key code

- `app/services/newstart/client.rb` — read-only NewStart API client
- `app/services/skus/sync_service.rb` — full-refresh upsert of the SKU catalog
- `app/services/photos/save_selections.rb` — persists processing-screen selections
- `app/jobs/sku_sync_job.rb` — Solid Queue background sync job
- `app/javascript/controllers/processing_controller.js` — SKU search, selection,
  and click-to-pin location tagging
