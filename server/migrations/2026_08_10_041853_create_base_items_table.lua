--- Migration: Create base_items table
return {
    up = function()
        Schema.create('base_items', function(table)
            table:id()
            table:string('name', 255)
            table:text('description'):nullable()
            table:string('icon', 255):nullable()
            table:float('weight'):default(0)
            table:boolean('is_takeable'):default(1):nullable()
            table:boolean('is_giveable'):default(1):nullable()
            table:boolean('is_dropable'):default(1):nullable()
            table:boolean('is_container'):default(0):nullable()
            table:boolean('is_useable'):default(0):nullable()
            table:boolean('is_stackable'):default(0):nullable()
            table:float('step'):nullable()
            table:string('step_key', 100):nullable()
            table:integer('max_stack_amount'):nullable()
            table:json('data'):nullable()
            table:json('actions'):nullable()
            table:timestamps()
        end)

        print('[Migration] Created base_items table')
    end,

    down = function()
        Schema.drop('base_items')
        print('[Migration] Dropped base_items table')
    end
}
