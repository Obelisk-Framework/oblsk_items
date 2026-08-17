-- modules/oblsk_items/tests/base_item_category_rename_spec.lua
-- Run from the repository root: lua5.4 tests/base_item_category_rename_spec.lua
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

test('migration renames item_categories to base_item_categories', function()
    local migration = dofile(scriptDir .. '../server/migrations/2026_08_16_200000_rename_item_categories_to_base_item_categories.lua')
    local sql = table.concat(captureStatements(migration.up), '\n')
    contains(sql, 'item_categories')
    contains(sql, 'base_item_categories')
    contains(sql, 'rename')
end)

test('migration renames base_items.item_category_id to base_item_category_id', function()
    local migration = dofile(scriptDir .. '../server/migrations/2026_08_16_200000_rename_item_categories_to_base_item_categories.lua')
    local sql = table.concat(captureStatements(migration.up), '\n')
    contains(sql, 'item_category_id')
    contains(sql, 'base_item_category_id')
end)

test('down migration reverses both renames', function()
    local migration = dofile(scriptDir .. '../server/migrations/2026_08_16_200000_rename_item_categories_to_base_item_categories.lua')
    local sql = table.concat(captureStatements(migration.down), '\n')
    contains(sql, 'base_item_categories')
    contains(sql, 'item_categories')
    contains(sql, 'base_item_category_id')
    contains(sql, 'item_category_id')
end)

test('BaseItemCategory model targets the renamed table', function()
    dofile(CORE_ROOT .. '/core/server/ORM/BaseModel.lua')
    local BaseItemCategory = dofile(scriptDir .. '../server/models/BaseItemCategory.lua')
    eq_ = BaseItemCategory.table
    if BaseItemCategory.table ~= 'base_item_categories' then
        error('expected table base_item_categories, got ' .. tostring(BaseItemCategory.table))
    end
end)

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then passed = passed + 1 else failures[#failures + 1] = { name = t.name, err = err } end
end
print(string.format('%d/%d passed', passed, #tests))
for _, f in ipairs(failures) do print(string.format('FAIL: %s\n  %s', f.name, f.err)) end
os.exit(#failures == 0 and 0 or 1)
