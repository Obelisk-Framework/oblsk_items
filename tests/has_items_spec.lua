local scriptDir = arg[0]:match('(.*/)') or './'
local ROOT = scriptDir .. '../../..'

dofile(ROOT .. '/tests/support/fivem_stubs.lua')
dofile(ROOT .. '/core/server/ORM/Dialects/Init.lua')
dofile(ROOT .. '/core/server/ORM/Dialects/MySQL.lua')
dofile(ROOT .. '/core/server/ORM/Dialects/Postgres.lua')
dofile(ROOT .. '/core/server/ORM/Database.lua')
dofile(ROOT .. '/core/server/ORM/QueryBuilder.lua')
dofile(ROOT .. '/core/server/ORM/Schema.lua')
dofile(ROOT .. '/core/server/ORM/BaseModel.lua')

Item = BaseModel:extend('items')
local HasItems = dofile(scriptDir .. '../server/services/HasItems.lua')

local Widget = { table = 'renamed_widgets', primaryKey = 'uuid' }
HasItems.apply(Widget, 'widget')
local function instance(Model, attributes)
    return setmetatable(attributes, { __index = Model })
end

local owner, reason = instance(Widget, {
    uuid = 'w-42', exists = true, itemOwnerType = 'spoofed',
}):itemOwner()
assert(reason == nil)
assert(owner.type == 'widget')
assert(owner.id == 'w-42')

local unsaved, unsavedReason = instance(Widget, { uuid = 'w-new', exists = false }):itemOwner()
assert(unsaved == nil)
assert(unsavedReason == 'Item owner must be persisted')

local missingId, missingIdReason = instance(Widget, { exists = true }):itemOwner()
assert(missingId == nil)
assert(missingIdReason == 'Item owner has no primary key')

local itemOwner, itemReason = instance(Item, { id = 5, exists = true }):itemOwner()
assert(itemReason == nil)
assert(itemOwner.type == 'item')
assert(itemOwner.id == 5)

print('HasItems contract: 4/4 passed')
