-- modules/oblsk_items/tests/item_service_use_spec.lua
-- Run:  lua5.4 modules/oblsk_items/tests/item_service_use_spec.lua
-- Covers ItemService.use: calls ActionService.execute(player, actionId, data)
-- for each pipeline entry of a useable item's base_item.actions, passing the
-- caller's already-resolved player straight through. No-ops for a
-- non-useable item. ItemService.use trusts its caller to hand it a real
-- Player (InventoryService.use, itself an Obelisk.onClient handler, only
-- ever runs with one already resolved) - it does no Player lookup of its
-- own.
local scriptDir = arg[0]:match('(.*/)') or './'

-- BaseItem is stubbed directly below (findSync/copyTable), so ItemService.lua
-- loads without needing the real ORM/BaseModel machinery.
dofile(scriptDir .. '../server/services/ItemService.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or 'assertion failed') .. '\n  expected: ' .. tostring(expected) .. '\n  actual:   ' .. tostring(actual), 2)
    end
end

--- Builds a fake BaseItem row (plain table, with the two methods ItemService
--- uses: findSync as a "class" lookup and copyTable as an instance method).
local function makeBaseItem(attributes)
    local baseItem = { attributes = attributes }
    function baseItem:copyTable(t)
        local copy = {}
        for k, v in pairs(t) do copy[k] = v end
        return copy
    end
    return baseItem
end

local function withStubs(opts, fn)
    local executeCalls = {}

    BaseItem = {}
    function BaseItem:find(id)
        return opts.baseItemsById[id]
    end

    ActionService = {
        resolveDbId = function(dbId) return opts.actionIdsByDbId[dbId] end,
        execute = function(player, actionId, data)
            table.insert(executeCalls, { player = player, actionId = actionId, data = data })
        end,
    }

    fn(executeCalls)
end

test('use: a useable item with a registered action calls ActionService.execute with the caller-supplied player', function()
    local baseItem = makeBaseItem({
        id = 1,
        is_useable = true,
        actions = { { action_id = 42, data = { foo = 'bar' } } },
    })
    local item = { attributes = { base_item_id = 1 } }
    local fakePlayer = { getSource = function(self) return 999 end }

    withStubs({
        baseItemsById = { [1] = baseItem },
        actionIdsByDbId = { [42] = 'item:notify' },
    }, function(executeCalls)
        ItemService.use(fakePlayer, item)

        eq(#executeCalls, 1)
        eq(executeCalls[1].player, fakePlayer)
        eq(executeCalls[1].actionId, 'item:notify')
        eq(executeCalls[1].data.foo, 'bar')
        eq(executeCalls[1].data.item, item)
        eq(executeCalls[1].data.baseItem, baseItem)
    end)
end)

test('use: onlyActionDbId runs only the matching pipeline entry', function()
    local baseItem = makeBaseItem({
        id = 3,
        is_useable = true,
        actions = {
            { action_id = 42, data = { foo = 'bar' } },
            { action_id = 43, data = { baz = 'qux' } },
        },
    })
    local item = { attributes = { base_item_id = 3 } }
    local fakePlayer = { getSource = function(self) return 999 end }

    withStubs({
        baseItemsById = { [3] = baseItem },
        actionIdsByDbId = { [42] = 'item:notify', [43] = 'item:consume_step' },
    }, function(executeCalls)
        ItemService.use(fakePlayer, item, 43)

        eq(#executeCalls, 1)
        eq(executeCalls[1].actionId, 'item:consume_step')
        eq(executeCalls[1].data.baz, 'qux')
    end)
end)

test('use: a non-useable item does nothing', function()
    local baseItem = makeBaseItem({
        id = 2,
        is_useable = false,
        actions = { { action_id = 42, data = {} } },
    })
    local item = { attributes = { base_item_id = 2 } }
    local fakePlayer = { getSource = function(self) return 999 end }

    withStubs({
        baseItemsById = { [2] = baseItem },
        actionIdsByDbId = { [42] = 'item:notify' },
    }, function(executeCalls)
        ItemService.use(fakePlayer, item)
        eq(#executeCalls, 0)
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
