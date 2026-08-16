-- core/modules/oblsk_items/tests/item_service_admin_spec.lua
-- Run from the repository root:  lua5.4 modules/oblsk_items/tests/item_service_admin_spec.lua
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

-- CharacterService stub: ItemService.add needs an active character to give to.
CharacterService = {}
function CharacterService.getActiveCharacterId(source)
    if source == 42 then return 100 end
    return nil
end

dofile(scriptDir .. '../server/services/ItemService.lua')

local makeFakeQueryBuilderModule = dofile(CORE_ROOT .. '/tests/support/fake_query_builder.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format('%s\n     expected: %s\n     actual:   %s', msg or 'assertion failed', tostring(expected), tostring(actual)), 2)
    end
end
local function truthy(v, msg) if not v then error(msg or 'expected truthy', 2) end end

local function withFakeDb(fn)
    local tables = {}
    local original = QueryBuilder
    QueryBuilder = makeFakeQueryBuilderModule(tables)
    local ok, err = pcall(fn, tables)
    QueryBuilder = original
    if not ok then error(err, 2) end
end

--------------------------------------------------------------------------------
-- listBaseItems
--------------------------------------------------------------------------------

test('listBaseItems: returns every base_items row', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'water', weight = 0.5 }, { id = 2, name = 'bread', weight = 0.3 } }
        local items = ItemService.listBaseItems()
        eq(#items, 2)
    end)
end)

--------------------------------------------------------------------------------
-- updateBaseItem
--------------------------------------------------------------------------------

test('updateBaseItem: updates whitelisted fields only', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'water', weight = 0.5, is_giveable = 1 } }
        local ok = ItemService.updateBaseItem(1, { weight = 0.8, is_giveable = 0, name = 'renamed' })
        truthy(ok)
        eq(tables.base_items[1].weight, 0.8)
        eq(tables.base_items[1].is_giveable, 0)
        eq(tables.base_items[1].name, 'water', 'name is not editable')
    end)
end)

test('updateBaseItem: invalidates the binding resolve cache', function()
    withFakeDb(function(tables)
        ItemService.resetBindingCacheForTests()
        tables.base_items = { { id = 1, name = 'water', weight = 0.5 } }
        tables.item_bindings = { { id = 1, key = 'test.key', base_item_id = 1 } }

        ItemService.registerRequirements('test-plugin', { ['test.key'] = { live = true } })

        local before = ItemService.binding('test.key')
        eq(before.weight, 0.5, 'cache should hold the pre-update weight')

        local ok = ItemService.updateBaseItem(1, { weight = 0.9 })
        truthy(ok)

        local after = ItemService.binding('test.key')
        eq(after.weight, 0.9, 'binding() must re-resolve after updateBaseItem invalidates the cache')

        ItemService.resetBindingCacheForTests()
    end)
end)

test('updateBaseItem: is_takeable=true forces is_giveable=true even if is_giveable was separately passed false', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'water', weight = 0.5, is_takeable = 0, is_giveable = 0 } }
        local ok = ItemService.updateBaseItem(1, { is_takeable = 1, is_giveable = 0 })
        truthy(ok)
        eq(tables.base_items[1].is_takeable, 1)
        eq(tables.base_items[1].is_giveable, true, 'is_takeable=true must force is_giveable true regardless of what was passed')
    end)
end)

test('updateBaseItem: is_takeable already true on the existing row forces is_giveable true even when not itself being changed', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'water', weight = 0.5, is_takeable = 1, is_giveable = 0 } }
        local ok = ItemService.updateBaseItem(1, { is_giveable = 0, weight = 0.9 })
        truthy(ok)
        eq(tables.base_items[1].is_giveable, true)
    end)
end)

test('updateBaseItem: is_takeable false leaves is_giveable exactly as passed', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'water', weight = 0.5, is_takeable = 0, is_giveable = 1 } }
        local ok = ItemService.updateBaseItem(1, { is_giveable = 0 })
        truthy(ok)
        eq(tables.base_items[1].is_giveable, 0)
    end)
end)

--------------------------------------------------------------------------------
-- createBaseItem
--------------------------------------------------------------------------------

test('createBaseItem: inserts a new row and returns its id', function()
    withFakeDb(function(tables)
        local id, reason = ItemService.createBaseItem({ name = 'bandage', weight = 0.1 })
        truthy(id ~= nil, 'expected an id')
        eq(reason, nil)
        eq(#tables.base_items, 1)
        eq(tables.base_items[1].name, 'bandage')
    end)
end)

test('createBaseItem: with a bindingKey, upserts item_bindings to point at the new item', function()
    withFakeDb(function(tables)
        local id = ItemService.createBaseItem({ name = 'fishing rod', weight = 1.5 }, 'fishing.rod')
        truthy(id ~= nil)
        eq(#tables.item_bindings, 1)
        eq(tables.item_bindings[1].key, 'fishing.rod')
        eq(tables.item_bindings[1].base_item_id, id)
    end)
end)

test('createBaseItem: bindingKey rebinds an existing key to the new item', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'old rod', weight = 1.0 } }
        tables.item_bindings = { { id = 1, key = 'fishing.rod', base_item_id = 1 } }
        local id = ItemService.createBaseItem({ name = 'new rod', weight = 1.2 }, 'fishing.rod')
        truthy(id ~= nil)
        eq(#tables.item_bindings, 1, 'must update the existing row, not insert a second one')
        eq(tables.item_bindings[1].base_item_id, id)
    end)
end)

test('createBaseItem: without a bindingKey, leaves item_bindings untouched', function()
    withFakeDb(function(tables)
        local id = ItemService.createBaseItem({ name = 'plain item', weight = 0.5 })
        truthy(id ~= nil)
        eq(tables.item_bindings, nil)
    end)
end)

test('createBaseItem: is_takeable=true forces is_giveable=true', function()
    withFakeDb(function(tables)
        local id = ItemService.createBaseItem({ name = 'wallet', weight = 0.1, is_takeable = true, is_giveable = false })
        truthy(id ~= nil)
        eq(tables.base_items[1].is_giveable, true)
    end)
end)

--------------------------------------------------------------------------------
-- giveToPlayer
--------------------------------------------------------------------------------

test('giveToPlayer: adds the item to the target\'s inventory', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'water', weight = 0.5 } }
        local ok = ItemService.giveToPlayer(42, 1, 3)
        truthy(ok)
        eq(#tables.items, 1)
        eq(tables.items[1].base_item_id, 1)
        eq(tables.items[1].amount, 3)
    end)
end)

test('giveToPlayer: fails with a reason when the base item does not exist', function()
    withFakeDb(function(tables)
        local ok, reason = ItemService.giveToPlayer(42, 999, 1)
        eq(ok, false)
        truthy(reason ~= nil)
    end)
end)

--------------------------------------------------------------------------------
-- listAvailableActions
--------------------------------------------------------------------------------

test('listAvailableActions: returns every actions row', function()
    withFakeDb(function(tables)
        tables.actions = { { id = 1, action_id = 'item:notify', label = 'Notify' }, { id = 2, action_id = 'item:consume_step', label = 'Consume' } }
        local actions = ItemService.listAvailableActions()
        eq(#actions, 2)
    end)
end)

--------------------------------------------------------------------------------
-- setBaseItemActions
--------------------------------------------------------------------------------

test('setBaseItemActions: writes the full replacement array of valid entries', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'water', actions = {} } }
        tables.actions = { { id = 5, action_id = 'item:notify', label = 'Notify' } }
        local ok = ItemService.setBaseItemActions(1, { { action_id = 5, data = { foo = 'bar' } } })
        truthy(ok)
        eq(#tables.base_items[1].actions, 1)
        eq(tables.base_items[1].actions[1].action_id, 5)
        eq(tables.base_items[1].actions[1].data.foo, 'bar')
    end)
end)

test('setBaseItemActions: skips entries referencing an unknown action_id', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'water', actions = {} } }
        tables.actions = { { id = 5, action_id = 'item:notify', label = 'Notify' } }
        local ok = ItemService.setBaseItemActions(1, {
            { action_id = 5, data = {} },
            { action_id = 999, data = {} },
        })
        truthy(ok)
        eq(#tables.base_items[1].actions, 1, 'the unknown action_id entry must be skipped')
        eq(tables.base_items[1].actions[1].action_id, 5)
    end)
end)

test('setBaseItemActions: empty array clears existing actions', function()
    withFakeDb(function(tables)
        tables.base_items = { { id = 1, name = 'water', actions = { { action_id = 5, data = {} } } } }
        tables.actions = { { id = 5, action_id = 'item:notify', label = 'Notify' } }
        local ok = ItemService.setBaseItemActions(1, {})
        truthy(ok)
        eq(#tables.base_items[1].actions, 0)
    end)
end)

print('Running ItemService admin unit tests\n')
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then passed = passed + 1; print('  ok   - ' .. t.name)
    else failures[#failures + 1] = t.name; print('  FAIL - ' .. t.name); print('         ' .. tostring(err):gsub('\n', '\n         ')) end
end
print(string.format('\n%d passed, %d failed', passed, #failures))
os.exit(#failures == 0 and 0 or 1)
