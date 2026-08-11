--- Migration: Create items table
return {
    up = function()
        Schema.create('items', function(table)
            table:id()
            table:integer('base_item_id')
            table:string('owner_type', 50)
            table:integer('owner_id')
            table:json('data'):nullable()
            table:integer('amount'):default(1):nullable()
            table:timestamps()

            table:index({'owner_type', 'owner_id'})
            table:foreign('base_item_id'):references('id'):on('base_items'):onDelete('RESTRICT')
        end)

        print('[Migration] Created items table')
    end,

    down = function()
        Schema.drop('items')
        print('[Migration] Dropped items table')
    end
}
