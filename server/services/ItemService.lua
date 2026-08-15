--- ItemService - runs a BaseItem's use pipeline (base_items.actions) through
--- the existing ActionService, and holds the pure step-consumption logic the
--- item:consume_step action delegates to.
ItemService = {}

--- True only for the DB's various truthy encodings of a boolean flag. A
--- TINYINT(1) column decodes to 0 or 1, and 0 is truthy in Lua, so callers
--- must not check the raw attribute directly.
--- @param v any
--- @return boolean
local function isTruthyFlag(v)
    return v == true or v == 1 or v == '1'
end

--- Subtract baseItem.step from item.data[baseItem.step_key], clamped to >= 0,
--- and persist the item. No-op if the item type has no step_key configured.
--- Kept separate from the item:consume_step action registration below so
--- this logic stays a plain, unit-testable function.
--- @param item table Item instance
--- @param baseItem table BaseItem instance
function ItemService.consumeStep(item, baseItem)
    local key = baseItem.attributes.step_key
    if not (key and baseItem.attributes.step) then return end

    item.attributes.data = item.attributes.data or {}
    local current = item.attributes.data[key] or 0
    item.attributes.data[key] = math.max(0, current - baseItem.attributes.step)
    item:saveSync()
end

--- Run a BaseItem's use pipeline for a given Item instance. Does nothing if
--- the item type isn't marked is_useable. Each pipeline entry's action_id is
--- an integer referencing actions.id (see ActionService); unknown ids are
--- skipped with a warning, not treated as a hard failure.
--- @param source number Player server ID
--- @param item table Item instance
function ItemService.use(source, item)
    local baseItem = BaseItem:findSync(item.attributes.base_item_id)
    if not baseItem or not isTruthyFlag(baseItem.attributes.is_useable) then return end

    item.baseItem = baseItem

    for _, entry in ipairs(baseItem.attributes.actions or {}) do
        local actionId = ActionService.resolveDbId(entry.action_id)
        if actionId then
            local data = baseItem:copyTable(entry.data or {})
            data.item = item
            data.baseItem = baseItem
            ActionService.execute(source, actionId, data)
        else
            print('[ItemService] WARNING: base_item #' .. baseItem.attributes.id .. ' references unknown action db id ' .. tostring(entry.action_id) .. ', skipping')
        end
    end
end

--- Total amount of `baseItem` the character behind `source` owns, summed across
--- every stack.
--- @param source number
--- @param baseItem table base_items row
--- @return number
local function ownedAmount(source, baseItem)
    local characterId = CharacterService.getActiveCharacterId(source)
    if not characterId then return 0 end

    local rows = QueryBuilder.new('items')
        :where('owner_type', 'character')
        :where('owner_id', characterId)
        :where('base_item_id', baseItem.id)
        :getSync()

    local total = 0
    for _, row in ipairs(rows) do
        total = total + (row.amount or 0)
    end
    return total
end

--- @param source number
--- @param baseItem table base_items row
--- @param amount number
--- @return boolean true if the character owns at least `amount` of `baseItem`
function ItemService.has(source, baseItem, amount)
    return ownedAmount(source, baseItem) >= amount
end

--- Merges `amount` into the character's existing stack of `baseItem` if one
--- exists, otherwise creates a new stack row. Does not split across
--- `max_stack_amount` — see the module-level note on this function's known
--- limitation (fine for currency-shaped items, not a general stacker).
--- @param source number
--- @param baseItem table base_items row
--- @param amount number
--- @return boolean, string|nil reason
function ItemService.add(source, baseItem, amount)
    if type(amount) ~= 'number' or amount <= 0 then
        return false, 'Invalid amount'
    end

    local characterId = CharacterService.getActiveCharacterId(source)
    if not characterId then
        return false, 'No active character'
    end

    local existing = QueryBuilder.new('items')
        :where('owner_type', 'character')
        :where('owner_id', characterId)
        :where('base_item_id', baseItem.id)
        :firstSync()

    if existing then
        QueryBuilder.new('items'):where('id', existing.id):update({
            amount = existing.amount + amount,
            updated_at = Database.now(),
        })
    else
        QueryBuilder.new('items'):insert({
            base_item_id = baseItem.id,
            owner_type = 'character',
            owner_id = characterId,
            amount = amount,
            data = {},
            created_at = Database.now(),
            updated_at = Database.now(),
        })
    end

    return true
end

--- Spends `amount` of `baseItem` from the character's stacks, oldest row
--- first, deleting any stack that reaches zero. Fails (no mutation at all) if
--- the character doesn't own enough — callers must check `ItemService.has`
--- first if they need to distinguish "not enough" from other failures, but
--- this also self-checks so it's safe to call directly.
--- @param source number
--- @param baseItem table base_items row
--- @param amount number
--- @return boolean, string|nil reason
function ItemService.remove(source, baseItem, amount)
    if type(amount) ~= 'number' or amount <= 0 then
        return false, 'Invalid amount'
    end

    local characterId = CharacterService.getActiveCharacterId(source)
    if not characterId then
        return false, 'No active character'
    end

    if not ItemService.has(source, baseItem, amount) then
        return false, 'Not enough items'
    end

    local rows = QueryBuilder.new('items')
        :where('owner_type', 'character')
        :where('owner_id', characterId)
        :where('base_item_id', baseItem.id)
        :orderBy('id', 'asc')
        :getSync()

    local remaining = amount
    for _, row in ipairs(rows) do
        if remaining <= 0 then break end
        local take = math.min(remaining, row.amount)
        remaining = remaining - take
        local newAmount = row.amount - take
        if newAmount <= 0 then
            QueryBuilder.new('items'):where('id', row.id):delete()
        else
            QueryBuilder.new('items'):where('id', row.id):update({
                amount = newAmount,
                updated_at = Database.now(),
            })
        end
    end

    return true
end

--- Binding registry: key -> { live = bool, hint = string|nil, uses = { [pluginName] = description|true } }.
--- Populated by ItemService.registerRequirements, called once per plugin at
--- boot (core/core/server/bootstrap.lua) with that plugin's
--- shared/config.lua Config.Requires.bindings table.
local registry = {}

--- Resolved-lookup cache: key -> BaseItem row | false (false = confirmed
--- unbound, cached so an unbound lookup doesn't re-hit the registry/DB every
--- call). `resolved[key] ~= nil` is the presence check, never truthiness.
local resolved = {}

--- @param pluginName string
--- @param bindingsTbl table|nil key -> { live, description, hint }
function ItemService.registerRequirements(pluginName, bindingsTbl)
    for key, def in pairs(bindingsTbl or {}) do
        local entry = registry[key] or { live = true, uses = {} }
        entry.live = entry.live and (def.live ~= false)
        entry.hint = entry.hint or def.hint
        entry.uses[pluginName] = def.description or true
        registry[key] = entry
    end
end

--- @param key string
--- @return table|nil the bound BaseItem's plain attributes table, or nil if unbound (or unrequired)
function ItemService.binding(key)
    local hit = resolved[key]
    if hit ~= nil then
        return hit or nil
    end

    if not registry[key] then
        print('[ItemService] WARNING: binding "' .. key .. '" is not required by any plugin')
        resolved[key] = false
        return nil
    end

    local row = QueryBuilder.new('item_bindings'):where('key', key):firstSync()
    if not row then
        resolved[key] = false
        return nil
    end

    local base = BaseItem:findSync(row.base_item_id)
    if not base then
        print('[ItemService] ERROR: binding "' .. key .. '" points at missing item #' .. tostring(row.base_item_id))
        resolved[key] = false
        return nil
    end

    resolved[key] = base.attributes
    return base.attributes
end

--- @param key string
--- @return boolean
function ItemService.hasBinding(key)
    return ItemService.binding(key) ~= nil
end

--- @param key string
--- @return boolean whether every plugin requiring this key allows a live
---   (no-restart) rebind. false for a key nobody requires.
function ItemService.bindingIsLive(key)
    local entry = registry[key]
    return entry ~= nil and entry.live == true
end

--- Test-only: clears the module-level registry/resolved-cache between spec
--- cases. Never called from production code paths.
function ItemService.resetBindingCacheForTests()
    registry = {}
    resolved = {}
end

--- @return string[] every key any loaded plugin has registered as required
function ItemService.getRequiredBindingKeys()
    local keys = {}
    for key in pairs(registry) do
        table.insert(keys, key)
    end
    return keys
end

--- @return table[] every base_items row
function ItemService.listBaseItems()
    return QueryBuilder.new('base_items'):getSync()
end

--- Whitelist-updates an existing base item. `name` and the `data`/`actions`
--- JSON columns are intentionally excluded — `name` is the lookup key
--- ItemService.binding() and every plugin's Config.Requires reference by
--- string, and data/actions are config-shaped, not admin-panel-shaped.
--- @param baseItemId number
--- @param attributes table any of: description, icon, weight, is_takeable,
---   is_giveable, is_dropable, is_container, is_useable, is_stackable, max_stack_amount
--- @return boolean
local EDITABLE_BASE_ITEM_FIELDS = {
    'description', 'icon', 'weight',
    'is_takeable', 'is_giveable', 'is_dropable', 'is_container', 'is_useable', 'is_stackable',
    'max_stack_amount',
}
function ItemService.updateBaseItem(baseItemId, attributes)
    local update = {}
    for _, field in ipairs(EDITABLE_BASE_ITEM_FIELDS) do
        if attributes[field] ~= nil then
            update[field] = attributes[field]
        end
    end
    QueryBuilder.new('base_items'):where('id', baseItemId):update(update)
    return true
end

--- @param attributes table see BaseItem.fillable for accepted keys
--- @return number|nil id, string|nil reason
function ItemService.createBaseItem(attributes)
    if not attributes.name or attributes.name == '' then
        return nil, 'Name is required'
    end
    local ok, result = pcall(function() return BaseItem:createSync(attributes) end)
    if not ok then
        return nil, 'Name already in use'
    end
    return result.attributes.id, nil
end

--- @param source number target player to give the item to
--- @param baseItemId number
--- @param amount number
--- @return boolean, string|nil reason
function ItemService.giveToPlayer(source, baseItemId, amount)
    local base = BaseItem:findSync(baseItemId)
    if not base then
        return false, 'Item not found'
    end
    return ItemService.add(source, base.attributes, amount)
end

return ItemService
