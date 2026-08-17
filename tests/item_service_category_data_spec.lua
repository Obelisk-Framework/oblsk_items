-- modules/oblsk_items/tests/item_service_category_data_spec.lua
-- Run from the repository root: lua5.4 tests/item_service_category_data_spec.lua
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
    tables = { base_items = {}, base_item_categories = {}, item_bindings = {} }
    local FakeQueryBuilderModule = makeFakeQueryBuilderModule(tables)
    QueryBuilder.new = FakeQueryBuilderModule.new
    ItemService.resetBindingCacheForTests()
    fn()
end

local MED_FIELDS = {
    { name = 'medical_description', type = 'text', required = true },
    { name = 'dosage_mg', type = 'number', required = false },
}

local function seedMedItem()
    local categoryId = ItemService.createCategory({ name = 'Medication', fields = MED_FIELDS })
    table.insert(tables.base_items, {
        id = 1, name = 'bandage', base_item_category_id = categoryId,
        data = '{"existing_key":"keep-me"}',
    })
    return 1
end

test('required field left empty is rejected, present in errors', function()
    withFreshState(function()
        local baseItemId = seedMedItem()
        local ok, errors = ItemService.updateBaseItemCategoryData(baseItemId, { medical_description = '' })
        eq(ok, false)
        eq(#errors, 1)
    end)
end)

test('non-required field left empty is accepted', function()
    withFreshState(function()
        local baseItemId = seedMedItem()
        local ok, errors = ItemService.updateBaseItemCategoryData(baseItemId, { medical_description = 'Stops bleeding', dosage_mg = '' })
        eq(ok, true)
        eq(#errors, 0)
    end)
end)

test('valid fields merge into data, existing unrelated keys survive', function()
    withFreshState(function()
        local baseItemId = seedMedItem()
        ItemService.updateBaseItemCategoryData(baseItemId, { medical_description = 'Stops bleeding' })
        local raw = tables.base_items[1].data
        truthy(raw:find('medical_description', 1, true))
        truthy(raw:find('existing_key', 1, true), 'unrelated existing data key must survive the merge')
    end)
end)

test('a values key not in the category schema is ignored', function()
    withFreshState(function()
        local baseItemId = seedMedItem()
        local ok = ItemService.updateBaseItemCategoryData(baseItemId, { medical_description = 'Stops bleeding', not_a_real_field = 'x' })
        eq(ok, true)
        local raw = tables.base_items[1].data
        eq(raw:find('not_a_real_field', 1, true), nil)
    end)
end)

test('item with no category set is a no-op', function()
    withFreshState(function()
        table.insert(tables.base_items, { id = 2, name = 'plain item', data = nil })
        local ok, errors = ItemService.updateBaseItemCategoryData(2, { anything = 'x' })
        eq(ok, true)
        eq(#errors, 0)
    end)
end)

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then passed = passed + 1 else failures[#failures + 1] = { name = t.name, err = err } end
end
print(string.format('%d/%d passed', passed, #tests))
for _, f in ipairs(failures) do print(string.format('FAIL: %s\n  %s', f.name, f.err)) end
os.exit(#failures == 0 and 0 or 1)
