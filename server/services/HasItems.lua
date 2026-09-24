--- HasItems defines the persisted owner identity used by items.owner_type/id.
--- Apply it with an explicit stable type; never infer the value from a table name.
HasItems = {}

--- @param Model table BaseModel subclass
--- @param ownerType string stable value stored in items.owner_type
function HasItems.apply(Model, ownerType)
    assert(type(Model) == 'table', 'HasItems.apply expects a model class')
    assert(type(ownerType) == 'string' and ownerType ~= '', 'HasItems.apply expects a non-empty owner type')

    Model.itemOwnerType = ownerType
    local primaryKey = Model.primaryKey or 'id'

    --- @return table|nil identity { type = string, id = any }
    --- @return string|nil reason
    function Model:itemOwner()
        if self.exists ~= true then
            return nil, 'Item owner must be persisted'
        end

        local id = self[primaryKey]
        if id == nil then
            return nil, 'Item owner has no primary key'
        end

        return { type = ownerType, id = id }, nil
    end
end

-- Models load before services; Characters opts in only when this optional
-- module is installed, while Items remains usable without oblsk_characters.
if type(Item) == 'table' and Item.itemOwnerType then
    HasItems.apply(Item, Item.itemOwnerType)
end
if type(Character) == 'table' and Character.itemOwnerType then
    HasItems.apply(Character, Character.itemOwnerType)
end

return HasItems
