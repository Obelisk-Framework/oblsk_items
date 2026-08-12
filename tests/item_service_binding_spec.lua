-- tests/item_service_binding_spec.lua
-- Run from the worktree root: lua5.4 tests/item_service_binding_spec.lua
-- CORE_ROOT is the path to the core repository root (6 levels up from this file:
-- tests/ -> worktree -> .claude -> oblsk_items -> modules -> core -> core-root)
local scriptDir = arg[0]:match('(.*/)') or './'
local CORE_ROOT = scriptDir .. '../../../../../..'

dofile(CORE_ROOT .. '/tests/support/fivem_stubs.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/Init.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/MySQL.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/Postgres.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Database.lua')
dofile(CORE_ROOT .. '/core/server/ORM/QueryBuilder.lua')
dofile(CORE_ROOT .. '/core/server/ORM/BaseModel.lua')

local makeFakeQueryBuilderModule = dofile(CORE_ROOT .. '/tests/support/fake_query_builder.lua')

dofile(scriptDir .. '../server/models/BaseItem.lua')
dofile(scriptDir .. '../server/models/ItemBinding.lua')
dofile(scriptDir .. '../server/services/ItemService.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or 'assertion failed') .. '\n  expected: ' .. tostring(expected) .. '\n  actual:   ' .. tostring(actual), 2)
    end
end

--- Fresh fake-DB tables + a fresh ItemService binding cache per test, so
--- tests don't leak state through ItemService's module-level `resolved` cache.
---
--- NOTE on fake_query_builder's real shape (differs from a first-draft guess):
--- `makeFakeQueryBuilderModule(tables)` takes the seed tables as its argument
--- and mutates that same table in place (see tests/support/fake_query_builder.lua's
--- docstring: "tableName -> array of row tables (shared, mutated in place across
--- calls)"). It does NOT return a wrapper object with a `.tables` field or a
--- `.new` field distinct from itself — the return value IS the fake QueryBuilder
--- module (has `.new(tableName)` directly on it). So we keep our own `tables`
--- reference and mutate that between assertions, and assign the returned module
--- itself to `QueryBuilder.new`.
local function withFreshState(fn)
    local tables = {
        base_items = {},
        item_bindings = {},
    }
    local FakeQueryBuilderModule = makeFakeQueryBuilderModule(tables)
    QueryBuilder.new = FakeQueryBuilderModule.new
    ItemService.resetBindingCacheForTests()
    fn(tables)
end

test('unbound key with no requirer resolves to nil and warns, never errors', function()
    withFreshState(function()
        local ok, result = pcall(ItemService.binding, 'currency.cash')
        eq(ok, true, 'binding() must not throw')
        eq(result, nil)
    end)
end)

test('key required but not assigned resolves to nil', function()
    withFreshState(function(tables)
        ItemService.registerRequirements('banking', { ['currency.cash'] = { live = false, description = 'deposits' } })
        eq(ItemService.binding('currency.cash'), nil)
        eq(ItemService.hasBinding('currency.cash'), false)
    end)
end)

test('assigned key resolves to the base item row', function()
    withFreshState(function(tables)
        tables.base_items[1] = { id = 1, name = 'cash' }
        tables.item_bindings[1] = { id = 1, key = 'currency.cash', base_item_id = 1 }
        ItemService.registerRequirements('banking', { ['currency.cash'] = { live = false } })

        local base = ItemService.binding('currency.cash')
        eq(base ~= nil, true)
        eq(base.attributes.id, 1)
        eq(ItemService.hasBinding('currency.cash'), true)
    end)
end)

test('assignment pointing at a deleted item resolves to nil, not an error', function()
    withFreshState(function(tables)
        tables.item_bindings[1] = { id = 1, key = 'currency.cash', base_item_id = 999 }
        ItemService.registerRequirements('banking', { ['currency.cash'] = { live = false } })

        eq(ItemService.binding('currency.cash'), nil)
    end)
end)

test('resolved lookups are cached — second call does not re-query', function()
    withFreshState(function(tables)
        tables.base_items[1] = { id = 1, name = 'cash' }
        tables.item_bindings[1] = { id = 1, key = 'currency.cash', base_item_id = 1 }
        ItemService.registerRequirements('banking', { ['currency.cash'] = { live = false } })

        ItemService.binding('currency.cash')
        tables.item_bindings = {}  -- if this were re-queried, the second call would now see nothing
        local base = ItemService.binding('currency.cash')
        eq(base.attributes.id, 1, 'expected the cached row, not a fresh (now-empty) query')
    end)
end)

test('live merges as logical AND across multiple requirers', function()
    withFreshState(function(tables)
        ItemService.registerRequirements('banking', { ['currency.cash'] = { live = false, description = 'deposits' } })
        ItemService.registerRequirements('shops', { ['currency.cash'] = { live = true, description = 'payments' } })
        eq(ItemService.bindingIsLive('currency.cash'), false, 'one false requirer must make the merged flag false')
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
