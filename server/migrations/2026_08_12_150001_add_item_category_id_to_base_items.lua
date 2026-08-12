--- Migration: Add item_category_id to base_items
return {
    up = function()
        Schema.table('base_items', function(table)
            table:foreignId('item_category_id'):nullable():constrained('item_categories'):onDelete('SET NULL')
        end)

        print('[Migration] Added item_category_id to base_items')
    end,

    down = function()
        Schema.dropColumn('base_items', 'item_category_id')
        print('[Migration] Dropped item_category_id from base_items')
    end
}
