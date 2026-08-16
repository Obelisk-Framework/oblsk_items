-- tests/item_service_category_spec.lua
-- Run from the repository root: lua5.4 tests/item_service_category_spec.lua
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

dofile(scriptDir .. '../server/models/BaseItem.lua')
dofile(scriptDir .. '../server/models/BaseItemCategory.lua')
dofile(scriptDir .. '../server/models/ItemBinding.lua')
dofile(scriptDir .. '../server/services/ItemService.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or 'assertion failed') .. '\n  expected: ' .. tostring(expected) .. '\n  actual:   ' .. tostring(actual), 2)
    end
end
local function truthy(v, msg) if not v then error(msg or 'expected truthy', 2) end end

local tables
local function withFreshState(fn)
    tables = {
        base_items = {},
        base_item_categories = {},
        item_bindings = {},
    }
    local FakeQueryBuilderModule = makeFakeQueryBuilderModule(tables)
    QueryBuilder.new = FakeQueryBuilderModule.new
    ItemService.resetBindingCacheForTests()
    fn()
end

test('createCategory creates a row and returns its id', function()
    withFreshState(function()
        local id, reason = ItemService.createCategory({ name = 'Medication' })
        truthy(id)
        eq(reason, nil)
        eq(#tables.base_item_categories, 1)
        eq(tables.base_item_categories[1].name, 'Medication')
    end)
end)

test('listCategories returns every row', function()
    withFreshState(function()
        ItemService.createCategory({ name = 'Medication' })
        ItemService.createCategory({ name = 'Weapons' })
        local list = ItemService.listCategories()
        eq(#list, 2)
    end)
end)

test('updateCategory updates name and fields', function()
    withFreshState(function()
        local id = ItemService.createCategory({ name = 'Medication' })
        local ok = ItemService.updateCategory(id, { fields = { { name = 'medical_description', type = 'text', required = true } } })
        truthy(ok)
        eq(tables.base_item_categories[1].fields ~= nil, true)
    end)
end)

test('deleteCategory succeeds when no base_items reference it', function()
    withFreshState(function()
        local id = ItemService.createCategory({ name = 'Medication' })
        local ok, reason = ItemService.deleteCategory(id)
        truthy(ok)
        eq(reason, nil)
        eq(#tables.base_item_categories, 0)
    end)
end)

test('deleteCategory refuses when a base_items row still references it', function()
    withFreshState(function()
        local id = ItemService.createCategory({ name = 'Medication' })
        table.insert(tables.base_items, { id = 1, name = 'bandage', base_item_category_id = id })
        local ok, reason = ItemService.deleteCategory(id)
        eq(ok, false)
        truthy(reason)
        eq(#tables.base_item_categories, 1)
    end)
end)

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then passed = passed + 1 else failures[#failures + 1] = { name = t.name, err = err } end
end
print(string.format('%d/%d passed', passed, #tests))
for _, f in ipairs(failures) do print(string.format('FAIL: %s\n  %s', f.name, f.err)) end
os.exit(#failures == 0 and 0 or 1)
