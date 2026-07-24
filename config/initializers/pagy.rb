require "pagy/extras/overflow"

# Default page size for paginated indexes.
Pagy::DEFAULT[:limit] = 25
# Clamp out-of-range page numbers to the last page instead of raising.
Pagy::DEFAULT[:overflow] = :last_page
