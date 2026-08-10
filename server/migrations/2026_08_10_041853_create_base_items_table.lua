--- Migration: Create base_items table
return {
    up = function()
        Schema.create('base_items', function(table)
            table:id()
            table:string('name', 255):notNullable()
            table:text('description')
            table:string('icon', 255)
            table:float('weight'):notNullable():default(0)
            table:boolean('is_takeable'):default(1)
            table:boolean('is_giveable'):default(1)
            table:boolean('is_dropable'):default(1)
            table:boolean('is_container'):default(0)
            table:boolean('is_useable'):default(0)
            table:boolean('is_stackable'):default(0)
            table:float('step')
            table:string('step_key', 100)
            table:integer('max_stack_amount')
            table:json('data')
            table:json('actions')
            table:timestamps()
        end)

        print('[Migration] Created base_items table')
    end,

    down = function()
        Schema.drop('base_items')
        print('[Migration] Dropped base_items table')
    end
}
