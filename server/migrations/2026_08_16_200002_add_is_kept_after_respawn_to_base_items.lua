--- Migration: Add is_kept_after_respawn to base_items
--- Defaults false: everything is lost on respawn today; only items an
--- admin explicitly flags (ID cards, etc.) survive, once oblsk_medic
--- builds the consuming respawn/inventory-clearing logic (out of scope
--- here — see docs/superpowers/specs/2026-08-16-base-item-category-fields-and-respawn-flag-design.md).
return {
    up = function()
        Schema.table('base_items', function(table)
            table:boolean('is_kept_after_respawn'):default(0):nullable()
        end)

        print('[Migration] Added is_kept_after_respawn to base_items')
    end,

    down = function()
        Schema.dropColumn('base_items', 'is_kept_after_respawn')
        print('[Migration] Dropped is_kept_after_respawn from base_items')
    end
}
