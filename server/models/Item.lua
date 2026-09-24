--- Item Model - a single owned instance of a BaseItem (a stack, a specific
--- partially-consumed item, etc). Ownership is polymorphic: owner_type is an
--- open string ('character', 'item', 'vehicle_trunk', 'vehicle_glovebox',
--- more later), owner_id points at whatever that type's table primary key
--- is. No FK constraint on owner_id since the target table varies.
Item = BaseModel:extend('items')

Item.primaryKey = 'id'
Item.timestamps = true

Item.fillable = {
    'base_item_id', 'owner_type', 'owner_id', 'data', 'amount',
}

Item.hidden = {}

Item.casts = {
    data = 'json',
}

Item.itemOwnerType = 'item'

function Item:baseItemRelation()
    return self:belongsTo(BaseItem, 'base_item_id', 'id')
end

--- Weight of this specific item instance. Flat base weight unless the item
--- type depletes (step_key set), in which case it scales by how much of
--- data[step_key] remains versus the base item's starting capacity.
--- Assumes self.baseItem has already been set directly (assign it yourself
--- after loading/constructing the BaseItem; :load('baseItemRelation')
--- populates self.relations.baseItemRelation, not self.baseItem, so it does
--- not satisfy this requirement). This method does not lazily load the
--- relation itself, callers control when that query happens.
--- @return number
function Item:getWeight()
    local baseItem = self.baseItem
    local key = baseItem.step_key
    local itemData = self.data or {}
    local baseData = baseItem.data or {}
    if key and baseItem.step and itemData[key] and baseData[key] then
        return baseItem.weight * (itemData[key] / baseData[key])
    end
    return baseItem.weight
end

--- Whether two Item instances are eligible to merge into one stacked row:
--- same base item, same owner, and byte-identical data. Does not check
--- is_stackable itself or max_stack_amount, both of which need the BaseItem,
--- not just the two Item instances; callers check those separately.
--- @param a table Item instance
--- @param b table Item instance
--- @return boolean
function Item.isStackableWith(a, b)
    if a.base_item_id ~= b.base_item_id then return false end
    if a.owner_type ~= b.owner_type then return false end
    if a.owner_id ~= b.owner_id then return false end
    return json.encode(a.data) == json.encode(b.data)
end

return Item
