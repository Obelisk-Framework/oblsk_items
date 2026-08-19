--- BaseItem Model - the item catalog/template. One row per item type.
--- `BaseModel` is a global provided by core; this module loads as part of
--- core's own resource (see the fold-modules-plugins design), not as a
--- separate FXServer resource.
BaseItem = BaseModel:extend('base_items')

BaseItem.primaryKey = 'id'
BaseItem.timestamps = true

BaseItem.fillable = {
    'name', 'description', 'icon', 'weight', 'base_item_category_id',
    'is_takeable', 'is_giveable', 'is_dropable', 'is_container', 'is_useable', 'is_stackable',
    'step', 'step_key', 'max_stack_amount',
    'data', 'actions',
    'is_kept_after_respawn',
}

BaseItem.hidden = {}

BaseItem.casts = {
    data = 'json',
    actions = 'json',
}

function BaseItem:category()
    return self:belongsTo(ItemCategory, 'item_category_id')
end

return BaseItem
