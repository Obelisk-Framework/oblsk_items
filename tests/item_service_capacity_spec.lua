-- modules/oblsk_items/tests/item_service_capacity_spec.lua
-- Run from the repository root:  lua5.4 modules/oblsk_items/tests/item_service_capacity_spec.lua
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

local FISH = { id = 10, weight = 2.0 }
local ROD = { id = 11, weight = 1.0, is_container = 1 }

local function withFreshState(seedItems, seedBaseItems, fn)
    local fake = makeFakeQueryBuilderModule({
        items = seedItems or {},
        base_items = seedBaseItems or {
            [1] = { id = 10, weight = 2.0 },
            [2] = { id = 11, weight = 1.0, is_container = 1 },
        },
    })
    QueryBuilder = fake
    ItemService.MaxSlots = 40
    ItemService.MaxWeight = 30.0
    fn(fake)
end

test('hasCapacity: true when well under both limits', function()
    withFreshState({}, nil, function()
        eq(ItemService.hasCapacity(999, FISH, 1), true)
    end)
end)

test('hasCapacity: false when the new stack would exceed MaxWeight', function()
    withFreshState({}, nil, function()
        ItemService.MaxWeight = 1.0
        local ok, reason = ItemService.hasCapacity(999, FISH, 1)
        eq(ok, false)
        eq(reason ~= nil, true)
    end)
end)

test('hasCapacity: false when the new stack would exceed MaxSlots', function()
    withFreshState({}, nil, function()
        ItemService.MaxSlots = 0
        local ok, reason = ItemService.hasCapacity(999, FISH, 1)
        eq(ok, false)
        eq(reason ~= nil, true)
    end)
end)

test('hasCapacity: merging into an existing stack only adds weight, not a slot', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 10, owner_type = 'character', owner_id = 5, amount = 1 },
    }, nil, function()
        ItemService.MaxSlots = 1 -- exactly one slot already used by the existing stack
        eq(ItemService.hasCapacity(999, FISH, 1), true, 'merge must not require a second slot')
    end)
end)

test('hasCapacity: forceNewStack always counts a new slot, even with a mergeable stack present', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 10, owner_type = 'character', owner_id = 5, amount = 1 },
    }, nil, function()
        ItemService.MaxSlots = 1
        eq(ItemService.hasCapacity(999, FISH, 1, true), false)
    end)
end)

test('hasCapacity: weight recurses into container contents', function()
    withFreshState({
        [1] = { id = 1, base_item_id = 11, owner_type = 'character', owner_id = 5, amount = 1 }, -- the rod bag, 1.0kg
        [2] = { id = 2, base_item_id = 10, owner_type = 'item', owner_id = 1, amount = 3 }, -- 3 fish inside it, 6.0kg
    }, nil, function()
        ItemService.MaxWeight = 7.5 -- 1.0 (bag) + 6.0 (contents) + 2.0 (new fish) = 9.0 > 7.5
        eq(ItemService.hasCapacity(999, FISH, 1), false)
        ItemService.MaxWeight = 9.0
        eq(ItemService.hasCapacity(999, FISH, 1), true)
    end)
end)

test('hasCapacity: no active character fails closed', function()
    withFreshState({}, nil, function()
        local ok, reason = ItemService.hasCapacity(1, FISH, 1)
        eq(ok, false)
        eq(reason ~= nil, true)
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
