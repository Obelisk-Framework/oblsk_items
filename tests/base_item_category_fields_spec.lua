-- modules/oblsk_items/tests/base_item_category_fields_spec.lua
-- Run from the repository root: lua5.4 tests/base_item_category_fields_spec.lua
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

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or 'assertion failed') .. '\n  expected: ' .. tostring(expected) .. '\n  actual:   ' .. tostring(actual), 2)
    end
end
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

test('migration adds fields json column to base_item_categories', function()
    local migration = dofile(scriptDir .. '../server/migrations/2026_08_16_200001_add_fields_to_base_item_categories.lua')
    local sql = table.concat(captureStatements(migration.up), '\n')
    contains(sql, 'base_item_categories')
    contains(sql, 'fields')
end)

test('BaseItemCategory casts fields as json', function()
    local BaseItemCategory = dofile(scriptDir .. '../server/models/BaseItemCategory.lua')
    eq(BaseItemCategory.casts.fields, 'json')
    local found = false
    for _, f in ipairs(BaseItemCategory.fillable) do if f == 'fields' then found = true end end
    eq(found, true, 'fields must be fillable')
end)

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then passed = passed + 1 else failures[#failures + 1] = { name = t.name, err = err } end
end
print(string.format('%d/%d passed', passed, #tests))
for _, f in ipairs(failures) do print(string.format('FAIL: %s\n  %s', f.name, f.err)) end
os.exit(#failures == 0 and 0 or 1)
