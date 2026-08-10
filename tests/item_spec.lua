--- Unit tests for the pure logic in the Item module (weight calculation,
--- stack eligibility). Run from the repository root:  lua5.4 tests/item_spec.lua
---
--- This module depends on core's ORM (BaseModel) being loadable stand-alone,
--- the same way core/tests/orm_spec.lua already loads it.
---
--- CORE_ROOT is a relative walk-up from this file to the core repo root.
--- The depth is architecturally fixed, not a guess: oblsk_items must live at
--- <core-root>/modules/oblsk_items/ for FXServer to load it as part of core
--- at all, so this file is always three levels below the core root
--- (tests/ -> oblsk_items/ -> modules/ -> core-root).
local scriptDir = arg[0]:match('(.*/)') or './'
local CORE_ROOT = scriptDir .. '../../..'

dofile(CORE_ROOT .. '/tests/support/fivem_stubs.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/Init.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/MySQL.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/Postgres.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Database.lua')
dofile(CORE_ROOT .. '/core/server/ORM/QueryBuilder.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Schema.lua')
dofile(CORE_ROOT .. '/core/server/ORM/BaseModel.lua')
dofile(scriptDir .. '../server/models/BaseItem.lua')
dofile(scriptDir .. '../server/models/Item.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = {name = name, fn = fn} end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format('%s\n     expected: %s\n     actual:   %s',
            msg or 'assertion failed', tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(v, msg)
    if not v then error(msg or 'expected a truthy value', 2) end
end

test('Item:getWeight() returns the flat base weight when step_key is not set', function()
    local baseItem = BaseItem.new({ weight = 5, step = nil, step_key = nil, data = {} })
    local item = Item.new({ data = {} })
    item.baseItem = baseItem
    eq(item:getWeight(), 5)
end)

test('Item:getWeight() scales weight by the remaining/capacity ratio when step_key is set', function()
    local baseItem = BaseItem.new({ weight = 1000, step = 100, step_key = 'fill_ml', data = { fill_ml = 1000 } })
    local item = Item.new({ data = { fill_ml = 900 } })
    item.baseItem = baseItem
    eq(item:getWeight(), 900)
end)

test('Item:getWeight() falls back to flat weight if the step_key is missing from data', function()
    local baseItem = BaseItem.new({ weight = 1000, step = 100, step_key = 'fill_ml', data = {} })
    local item = Item.new({ data = {} })
    item.baseItem = baseItem
    eq(item:getWeight(), 1000)
end)

test('Item.isStackableWith: identical data on the same base_item_id/owner is stackable', function()
    local a = Item.new({ base_item_id = 1, owner_type = 'character', owner_id = 1, data = { fill_ml = 1000 } })
    local b = Item.new({ base_item_id = 1, owner_type = 'character', owner_id = 1, data = { fill_ml = 1000 } })
    truthy(Item.isStackableWith(a, b), 'identical data stacks')
end)

test('Item.isStackableWith: different data on the same base_item_id/owner is not stackable', function()
    local a = Item.new({ base_item_id = 1, owner_type = 'character', owner_id = 1, data = { fill_ml = 1000 } })
    local b = Item.new({ base_item_id = 1, owner_type = 'character', owner_id = 1, data = { fill_ml = 900 } })
    eq(Item.isStackableWith(a, b), false)
end)

test('Item.isStackableWith: different owner is not stackable even with identical data', function()
    local a = Item.new({ base_item_id = 1, owner_type = 'character', owner_id = 1, data = {} })
    local b = Item.new({ base_item_id = 1, owner_type = 'character', owner_id = 2, data = {} })
    eq(Item.isStackableWith(a, b), false)
end)

--------------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------------
print('Running Item unit tests\n')
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
        print('  ok   - ' .. t.name)
    else
        failures[#failures + 1] = t.name
        print('  FAIL - ' .. t.name)
        print('         ' .. tostring(err):gsub('\n', '\n         '))
    end
end

print(string.format('\n%d passed, %d failed', passed, #failures))
os.exit(#failures == 0 and 0 or 1)
