module Catalog
  # Full-replaces a community's configurator step tree from /steps. Each step
  # holds ordered categories, each of which holds ordered subcategories. The API
  # exposes display names + sort order only (no category codes), so this is a
  # presentation tree, not code-joinable to products. Small enough to rebuild
  # with plain AR writes each run.
  class StepsSyncer
    def self.call(community, steps, **opts)
      new(community, steps, **opts).call
    end

    def initialize(community, steps)
      @community = community
      @steps = steps || []
    end

    # Returns the number of steps written.
    def call
      Step.transaction do
        @community.steps.destroy_all
        @steps.each do |s|
          name = s["step"].presence
          next unless name

          step = @community.steps.create!(
            step: name,
            sortorder: Casts.integer(s["sortorder"]),
            area_associations: s["area_associations"]
          )
          build_categories(step, s["categories"])
        end
      end
      @community.steps.count
    end

    private

    def build_categories(step, categories)
      Array(categories).each do |c|
        category = step.step_categories.create!(
          name: c["category"],
          sortorder: Casts.integer(c["sortorder"])
        )
        Array(c["subcategories"]).each do |sc|
          category.step_subcategories.create!(
            name: sc["subcategory"],
            sortorder: Casts.integer(sc["sortorder"])
          )
        end
      end
    end
  end
end
