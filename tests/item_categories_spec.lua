-- tests/item_categories_spec.lua
-- Run from the repository root: lua5.4 tests/item_categories_spec.lua
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
dofile(CORE_ROOT .. '/core/server/ORM/Schema.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function contains(haystack, needle, msg)
    if not haystack:lower():find(needle:lower(), 1, true) then
        error((msg or 'expected substring not found') .. '\n  looking for: ' .. needle .. '\n  in: ' .. haystack, 2)
    end
end

local function captureStatements(fn)
    local statements = {}
    local original = Database.querySync
    Database.querySync = function(sql, params)
        table.insert(statements, sql)
        return {}
    end
    fn()
    Database.querySync = original
    return statements
end

test('item_categories migration creates the item_categories table', function()
    local migration = dofile(scriptDir .. '../server/migrations/2026_08_12_150000_create_item_categories_table.lua')
    local sql = table.concat(captureStatements(migration.up), '\n')
    contains(sql, 'item_categories')
    contains(sql, 'name')
end)

test('add_item_category_id migration adds a nullable FK on base_items with ON DELETE SET NULL', function()
    local migration = dofile(scriptDir .. '../server/migrations/2026_08_12_150001_add_item_category_id_to_base_items.lua')
    local sql = table.concat(captureStatements(migration.up), '\n')
    contains(sql, 'base_items')
    contains(sql, 'item_category_id')
    contains(sql, 'item_categories')
    contains(sql, 'SET NULL')
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
