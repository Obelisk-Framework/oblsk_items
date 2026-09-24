-- modules/oblsk_items/tests/item_service_inventory_spec.lua
-- Run from the repository root:  lua5.4 modules/oblsk_items/tests/item_service_inventory_spec.lua
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
dofile(ROOT .. '/core/server/Traits/HasItems.lua')
dofile(scriptDir .. '../server/models/BaseItem.lua')
dofile(scriptDir .. '../server/models/Item.lua')
local StorageUnit = BaseModel:extend('storage_units')
HasItems.apply(StorageUnit, 'storage_unit')

local makeFakeQueryBuilderModule = dofile(ROOT .. '/tests/support/fake_query_builder.lua')

CharacterService = { sessionCharacters = { [999] = 5 } }
function CharacterService.getActiveCharacterId(source)
    return CharacterService.sessionCharacters[source]
end

dofile(scriptDir .. '../server/services/ItemService.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or 'assertion failed') .. '\n  expected: ' .. tostring(expected) .. '\n  actual:   ' .. tostring(actual), 2)
    end
end

local CASH = { id = 1, is_stackable = true, max_stack_amount = nil }

local function withFreshState(seedItems, fn)
    local fake = makeFakeQueryBuilderModule({ items = seedItems or {} })
    QueryBuilder = fake
    fn(fake)
end

test('has: false when the character owns none of the item', function()
    withFreshState({}, function()
        eq(ItemService.has(999, CASH, 50), false)
    end)
end)

test('has: true when owned amount meets the requested amount', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 50 },
    }, function()
        eq(ItemService.has(999, CASH, 50), true)
        eq(ItemService.has(999, CASH, 51), false)
    end)
end)

test('has: sums across multiple stacks', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 20 },
        [2] = { id = 2, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 30 },
    }, function()
        eq(ItemService.has(999, CASH, 50), true)
    end)
end)

test('add: creates a new stack when the character owns none', function()
    withFreshState({}, function(fake)
        local ok = ItemService.add(999, CASH, 100)
        eq(ok, true)
        local rows = fake.new('items'):where('owner_type', 'character'):where('owner_id', 5):get()
        eq(#rows, 1)
        eq(rows[1].amount, 100)
    end)
end)

test('add: accepts any persisted HasItems model without the characters module', function()
    withFreshState({}, function(fake)
        local characterService = CharacterService
        CharacterService = nil

        local owner = StorageUnit.new({ id = 900 })
        owner.exists = true
        local succeeded, ok, reason = pcall(ItemService.add, owner, CASH, 10)

        CharacterService = characterService
        if not succeeded then error(ok) end
        eq(ok, true, reason)
        local rows = fake.new('items'):where('owner_type', 'storage_unit'):where('owner_id', 900):get()
        eq(#rows, 1)
        eq(rows[1].amount, 10)
    end)
end)

test('add: merges into an existing stack of the same item', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 20 },
    }, function(fake)
        local ok = ItemService.add(999, CASH, 30)
        eq(ok, true)
        local rows = fake.new('items'):where('owner_type', 'character'):where('owner_id', 5):get()
        eq(#rows, 1)
        eq(rows[1].amount, 50)
    end)
end)

test('add: forceNewStack skips merging and always inserts a new row, each keeping its own data', function()
    withFreshState({}, function(fake)
        local ok1 = ItemService.add(999, CASH, 1, { textureId = 0, colorLabel = 'White' }, true)
        local ok2 = ItemService.add(999, CASH, 1, { textureId = 1, colorLabel = 'Black' }, true)
        eq(ok1, true)
        eq(ok2, true)
        local rows = Item:where('owner_type', 'character'):where('owner_id', 5):get()
        eq(#rows, 2)
        eq(rows[1].amount, 1)
        eq(rows[2].amount, 1)
        eq(rows[1].data.textureId, 0)
        eq(rows[1].data.colorLabel, 'White')
        eq(rows[2].data.textureId, 1)
        eq(rows[2].data.colorLabel, 'Black')
    end)
end)

test('has and remove: use a persisted model owner identity', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 1, owner_type = 'item', owner_id = 900, amount = 50 },
    }, function(fake)
        local owner = Item.new({ id = 900 })
        owner.exists = true
        eq(ItemService.has(owner, CASH, 50), true)
        eq(ItemService.remove(owner, CASH, 20), true)
        eq(fake.new('items'):where('id', 1):first().amount, 30)
    end)
end)

test('remove: fails and mutates nothing when the character owns less than requested', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 10 },
    }, function(fake)
        local ok, reason = ItemService.remove(999, CASH, 50)
        eq(ok, false)
        eq(reason ~= nil, true)
        eq(fake.new('items'):where('id', 1):first().amount, 10)
    end)
end)

test('remove: decrements a single stack and deletes it if it hits zero', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 50 },
    }, function(fake)
        eq(ItemService.remove(999, CASH, 50), true)
        eq(fake.new('items'):where('id', 1):first(), nil)
    end)
end)

test('remove: spends across multiple stacks oldest-row-first', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 20 },
        [2] = { id = 2, base_item_id = 1, owner_type = 'character', owner_id = 5, amount = 30 },
    }, function(fake)
        eq(ItemService.remove(999, CASH, 25), true)
        eq(fake.new('items'):where('id', 1):first(), nil)
        eq(fake.new('items'):where('id', 2):first().amount, 25)
    end)
end)

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
        print('  PASS  ' .. t.name)
    else
        table.insert(failures, { name = t.name, err = err })
        print('  FAIL  ' .. t.name .. '\n        ' .. tostring(err))
    end
end

print(('\n%d passed, %d failed'):format(passed, #failures))
os.exit(#failures > 0 and 1 or 0)
