--- Built-in actions usable from any base_items.actions pipeline entry.
--- Registered once at module load, same mechanism every other action in the
--- framework uses (see core/server/Services/ActionService.lua).

ActionService.register('item:consume_step', function(source, data)
    if not (data.item and data.baseItem) then return end
    ItemService.consumeStep(data.item, data.baseItem)
end, { label = 'Consume one step of a depletable item' })

ActionService.register('item:notify', function(source, data)
    NotificationService.notify(source, {
        type = data.kind or 'info',
        title = data.title,
        description = data.text
    })
end, { label = 'Send a notification as an item-use side effect' })
