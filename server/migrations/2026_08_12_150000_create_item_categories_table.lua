--- Migration: Create item_categories table
return {
    up = function()
        Schema.create('item_categories', function(table)
            table:id()
            table:string('name', 100)
            table:timestamps()
        end)

        print('[Migration] Created item_categories table')
    end,

    down = function()
        Schema.drop('item_categories')
        print('[Migration] Dropped item_categories table')
    end
}
