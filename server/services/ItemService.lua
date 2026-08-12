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

return ItemService
