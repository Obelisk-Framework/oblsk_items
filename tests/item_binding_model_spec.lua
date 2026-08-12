-- tests/item_binding_model_spec.lua
-- Run from the repository root: lua5.4 tests/item_binding_model_spec.lua
-- CORE_ROOT is the path to the core repository root. oblsk_items lives at
-- <core-root>/modules/oblsk_items/, so this file is three levels below the
-- core root: tests/ -> oblsk_items -> modules -> core-root.
local scriptDir = arg[0]:match('(.*/)') or './'
local CORE_ROOT = scriptDir .. '../../..'

dofile(CORE_ROOT .. '/tests/support/fivem_stubs.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/Init.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/MySQL.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/Postgres.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Database.lua')
dofile(CORE_ROOT .. '/core/server/ORM/QueryBuilder.lua')
dofile(CORE_ROOT .. '/core/server/ORM/BaseModel.lua')

local makeFakeQueryBuilderModule = dofile(CORE_ROOT .. '/tests/support/fake_query_builder.lua')

dofile(scriptDir .. '../server/models/ItemBinding.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or 'assertion failed') .. '\n  expected: ' .. tostring(expected) .. '\n  actual:   ' .. tostring(actual), 2)
    end
end

test('ItemBinding is keyed on id, fillable exposes key/base_item_id', function()
    eq(ItemBinding.primaryKey, 'id')
    local sawKey, sawBaseItemId = false, false
    for _, field in ipairs(ItemBinding.fillable) do
        if field == 'key' then sawKey = true end
        if field == 'base_item_id' then sawBaseItemId = true end
    end
    eq(sawKey, true, 'fillable must include "key"')
    eq(sawBaseItemId, true, 'fillable must include "base_item_id"')
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
