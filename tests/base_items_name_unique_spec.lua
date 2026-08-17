-- tests/base_items_name_unique_spec.lua
-- Run from the repository root: lua5.4 tests/base_items_name_unique_spec.lua
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
    if not haystack:find(needle, 1, true) then
        error((msg or 'expected substring not found') .. '\n  looking for: ' .. needle .. '\n  in: ' .. haystack, 2)
    end
end

test('migration adds a unique index on base_items.name', function()
    local migration = dofile(scriptDir .. '../server/migrations/2026_08_12_100000_add_unique_to_base_items_name.lua')
    local statements = {}
    -- Schema.table emits ALTER statements; capture them instead of hitting a real DB.
    local originalExecute = Database.query
    Database.query = function(sql, params)
        table.insert(statements, sql)
        return {}
    end
    migration.up()
    Database.query = originalExecute

    local sawUnique = false
    for _, sql in ipairs(statements) do
        if sql:lower():find('unique') and sql:lower():find('base_items') then
            sawUnique = true
        end
    end
    if not sawUnique then
        error('expected a UNIQUE index/constraint statement touching base_items, got:\n  ' .. table.concat(statements, '\n  '))
    end
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
