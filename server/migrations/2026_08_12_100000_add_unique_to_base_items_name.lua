return {
    up = function()
        Schema.table('base_items', function(table)
            table:unique('name')
        end)

        print('[Migration] Added unique index to base_items.name')
    end,

    down = function()
        -- Schema has no dropUnique helper yet; document intent, no-op like
        -- other irreversible-in-practice down() bodies in this codebase.
        print('[Migration] base_items.name unique index left in place (no dropUnique helper)')
    end
}
