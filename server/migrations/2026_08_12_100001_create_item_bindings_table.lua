return {
    up = function()
        Schema.create('item_bindings', function(table)
            table:id()
            table:string('key', 64):unique()
            table:foreignId('base_item_id'):constrained('base_items')
            table:string('updated_by', 64):nullable()
            table:timestamp('updated_at'):nullable()
        end)

        print('[Migration] Created item_bindings table')
    end,

    down = function()
        Schema.drop('item_bindings')
        print('[Migration] Dropped item_bindings table')
    end
}
