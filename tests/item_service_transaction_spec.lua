local scriptDir = arg[0]:match('(.*/)') or './'
local ROOT = scriptDir .. '../../..'
dofile(ROOT .. '/tests/support/fivem_stubs.lua')
dofile(ROOT .. '/core/server/ORM/Dialects/Init.lua')
dofile(ROOT .. '/core/server/ORM/Dialects/MySQL.lua')
dofile(ROOT .. '/core/server/ORM/Dialects/Postgres.lua')
dofile(ROOT .. '/core/server/ORM/Database.lua')
dofile(ROOT .. '/core/server/ORM/QueryBuilder.lua')
local makeFake = dofile(ROOT .. '/tests/support/fake_query_builder.lua')
local fake = makeFake({ items = {
    [1] = { id = 1, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 20 },
    [2] = { id = 2, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 30 },
} })
QueryBuilder = fake
Item = {}
function Item:where(column, value) return QueryBuilder.new('items'):where(column, value) end
CharacterService = { getActiveCharacterId = function(source) return source == 999 and 5 or nil end }
dofile(scriptDir .. '../server/services/ItemService.lua')

local cash = { id = 1, is_stackable = true }
local debit = Database.newTransaction()
assert(ItemService.queueRemove(debit, 999, cash, 25) == true)
assert(#debit.queries == 2)
assert(debit.queries[1].expectedAffectedRows == 1 and debit.queries[2].expectedAffectedRows == 1)
assert(fake.new('items'):where('id', 1):first().amount == 20, 'queueRemove mutated inventory before commit')

local credit = Database.newTransaction()
assert(ItemService.queueAdd(credit, 999, cash, 30) == true)
assert(#credit.queries == 1 and credit.queries[1].expectedAffectedRows == 1)
assert(fake.new('items'):where('id', 1):first().amount == 20, 'queueAdd mutated inventory before commit')

local insert = Database.newTransaction()
assert(ItemService.queueAdd(insert, 999, { id = 2 }, 1, { variant = 3 }, true) == true)
assert(#insert.queries == 1 and insert.queries[1].query:find('INSERT INTO items', 1, true))
assert(insert.queries[1].expectedAffectedRows == 1)

local rejected = Database.newTransaction()
local ok = ItemService.queueRemove(rejected, 999, cash, 100)
assert(ok == false and #rejected.queries == 0, 'insufficient inventory must queue no writes')
print('ItemService transactional inventory planning: 9/9 passed')
