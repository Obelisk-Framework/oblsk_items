--- Migration: Add fields json column to base_item_categories
--- Shape: [{ name, type, required, options }], type in text|number|boolean|select.
--- See docs/superpowers/specs/2026-08-16-base-item-category-fields-and-respawn-flag-design.md.
return {
    up = function()
        Schema.table('base_item_categories', function(table)
            table:json('fields'):nullable()
        end)

        print('[Migration] Added fields to base_item_categories')
    end,

    down = function()
        Schema.dropColumn('base_item_categories', 'fields')
        print('[Migration] Dropped fields from base_item_categories')
    end
}
