--- ItemService - runs a BaseItem's use pipeline (base_items.actions) through
--- the existing ActionService, and holds the pure step-consumption logic the
--- item:consume_step action delegates to.
ItemService = {}

--- Flat, framework-wide carry limits (not per-character for v1 — see
--- docs/superpowers/specs/2026-08-16-fishing-plugin-design.md). Public and
--- mutable so tests (and, later, an admin setting) can override them.
ItemService.MaxSlots = 40
ItemService.MaxWeight = 30.0

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
    item:save()
end

--- Run a BaseItem's use pipeline for a given Item instance. Does nothing if
--- the item type isn't marked is_useable. Each pipeline entry's action_id is
--- an integer referencing actions.id (see ActionService); unknown ids are
--- skipped with a warning, not treated as a hard failure.
--- @param player table Player instance
--- @param item table Item instance
--- @param onlyActionDbId number|nil when given, run only the pipeline
---   entry(ies) whose action_id matches this actions.id (a context-menu
---   click on one specific resolved action); when nil, run every pipeline
---   entry as before (the generic "Use" fallback for items without
---   per-action UI yet)
function ItemService.use(player, item, onlyActionDbId)
    local baseItem = BaseItem:find(item.attributes.base_item_id)
    if not baseItem or not isTruthyFlag(baseItem.attributes.is_useable) then return end

    item.baseItem = baseItem

    for _, entry in ipairs(baseItem.attributes.actions or {}) do
        if onlyActionDbId == nil or entry.action_id == onlyActionDbId then
            local actionId = ActionService.resolveDbId(entry.action_id)
            if actionId then
                local data = baseItem:copyTable(entry.data or {})
                data.item = item
                data.baseItem = baseItem
                ActionService.execute(player, actionId, data)
            else
                print('[ItemService] WARNING: base_item #' .. baseItem.attributes.id .. ' references unknown action db id ' .. tostring(entry.action_id) .. ', skipping')
            end
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
        :get()

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
--- @param data table|nil per-instance data merged onto the stack row (new
---   stacks only — an existing stack is never overwritten with different
---   instance data, since merging two different garments into one stack
---   would lose one side's component/drawable/texture)
--- @param forceNewStack boolean|nil when truthy, skip the existing-stack
---   lookup entirely and always insert a new row — an escape hatch for
---   callers whose `data` distinguishes otherwise-identical base items
---   (e.g. clothing variants sharing one base_item_id) and must never be
---   silently merged into an existing stack
--- @return boolean, string|nil reason
function ItemService.add(source, baseItem, amount, data, forceNewStack)
    if type(amount) ~= 'number' or amount <= 0 then
        return false, 'Invalid amount'
    end

    local characterId = CharacterService.getActiveCharacterId(source)
    if not characterId then
        return false, 'No active character'
    end

    local existing = not forceNewStack and QueryBuilder.new('items')
        :where('owner_type', 'character')
        :where('owner_id', characterId)
        :where('base_item_id', baseItem.id)
        :first()

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
            data = data or {},
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
        :get()

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

--- Per-unit weight of a base_items row, scaled by a depleting item's
--- remaining step data the same way Item:getWeight() computes it for a
--- single instance — duplicated here (rather than reusing the Item model)
--- because hasCapacity works off raw base_items/items rows via
--- QueryBuilder, not loaded Item/BaseItem model instances.
--- @param base table base_items row
--- @param row table items row (may be nil for a not-yet-existing stack)
--- @return number
local function unitWeight(base, row)
    local w = base.weight or 0
    local key = base.step_key
    if key and base.step and row and row.data and base.data and row.data[key] and base.data[key] then
        return w * (row.data[key] / base.data[key])
    end
    return w
end

--- Total weight of everything a character carries: every top-level
--- character-owned stack, plus recursively every item stored inside a
--- container the character owns (owner_type = 'item', chained owner_id).
--- @param characterId number
--- @return number
local function totalCarriedWeight(characterId)
    local baseItemsById = {}
    local function base(id)
        if baseItemsById[id] == nil then
            baseItemsById[id] = QueryBuilder.new('base_items'):where('id', id):first() or false
        end
        return baseItemsById[id] or nil
    end

    local total = 0
    local function sumOwnedBy(ownerType, ownerId)
        local rows = QueryBuilder.new('items'):where('owner_type', ownerType):where('owner_id', ownerId):get()
        for _, row in ipairs(rows) do
            local b = base(row.base_item_id)
            if b then
                total = total + unitWeight(b, row) * (row.amount or 1)
                sumOwnedBy('item', row.id) -- recurse into this row's own contents, if any
            end
        end
    end

    sumOwnedBy('character', characterId)
    return total
end

--- Whether granting `amount` of `baseItem` to `source`'s active character
--- would exceed ItemService.MaxSlots or ItemService.MaxWeight. Mirrors the
--- same existing-stack lookup ItemService.add itself does, so the
--- projection matches what add() will actually do.
--- @param source number
--- @param baseItem table base_items row
--- @param amount number
--- @param forceNewStack boolean|nil
--- @return boolean ok
--- @return string|nil reason
function ItemService.hasCapacity(source, baseItem, amount, forceNewStack)
    local characterId = CharacterService.getActiveCharacterId(source)
    if not characterId then
        return false, 'No active character'
    end

    local existing = not forceNewStack and QueryBuilder.new('items')
        :where('owner_type', 'character')
        :where('owner_id', characterId)
        :where('base_item_id', baseItem.id)
        :first()

    local currentSlots = #QueryBuilder.new('items'):where('owner_type', 'character'):where('owner_id', characterId):get()
    local projectedSlots = currentSlots + (existing and 0 or 1)
    if projectedSlots > ItemService.MaxSlots then
        return false, 'Not enough inventory space'
    end

    local projectedWeight = totalCarriedWeight(characterId) + unitWeight(baseItem, nil) * amount
    if projectedWeight > ItemService.MaxWeight then
        return false, 'Too heavy to carry'
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

    local row = QueryBuilder.new('item_bindings'):where('key', key):first()
    if not row then
        resolved[key] = false
        return nil
    end

    local base = BaseItem:find(row.base_item_id)
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

--- Shared upsert logic for pointing a binding key at a base item — the same
--- inline logic ItemService.createBaseItem used at creation time, extracted
--- so ItemService.setBinding can reuse it for post-creation rebinds too.
--- Invalidates the resolve cache for `key` either way.
--- @param key string
--- @param baseItemId number
local function upsertBinding(key, baseItemId)
    local existingBinding = QueryBuilder.new('item_bindings'):where('key', key):first()
    if existingBinding then
        QueryBuilder.new('item_bindings'):where('id', existingBinding.id):update({
            base_item_id = baseItemId,
            updated_at = Database.now(),
        })
    else
        QueryBuilder.new('item_bindings'):insert({
            key = key,
            base_item_id = baseItemId,
            updated_at = Database.now(),
        })
    end
    resolved[key] = nil
end

--- @return table[] every item_bindings row, each with its base_item_id and
---   (when the bound item still exists) the bound item's name
function ItemService.listBindings()
    local rows = QueryBuilder.new('item_bindings'):get()
    local out = {}
    for _, row in ipairs(rows) do
        local base = QueryBuilder.new('base_items'):where('id', row.base_item_id):first()
        table.insert(out, {
            id = row.id,
            key = row.key,
            base_item_id = row.base_item_id,
            base_item_name = base and base.name or nil,
        })
    end
    return out
end

--- Points `key` at `baseItemId`, upserting the item_bindings row (same
--- semantics as createBaseItem's bindingKey argument, usable after creation).
--- @param key string
--- @param baseItemId number
--- @return boolean
function ItemService.setBinding(key, baseItemId)
    upsertBinding(key, baseItemId)
    return true
end

--- Deletes the item_bindings row for `key`, if any.
--- @param key string
--- @return boolean
function ItemService.clearBinding(key)
    QueryBuilder.new('item_bindings'):where('key', key):delete()
    resolved[key] = nil
    return true
end

--- @return table[] every base_items row
function ItemService.listBaseItems()
    return QueryBuilder.new('base_items'):get()
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

    -- "Can be taken" always implies "Can be traded": if is_takeable ends up
    -- true (whether just set here or already true on the existing row),
    -- force is_giveable true too, regardless of what was separately passed.
    local resolvedTakeable = update.is_takeable
    if resolvedTakeable == nil then
        local existing = QueryBuilder.new('base_items'):where('id', baseItemId):first()
        resolvedTakeable = existing and existing.is_takeable
    end
    if isTruthyFlag(resolvedTakeable) then
        update.is_giveable = true
    end

    QueryBuilder.new('base_items'):where('id', baseItemId):update(update)

    for key, value in pairs(resolved) do
        if value and value.id == baseItemId then
            resolved[key] = nil
        end
    end

    return true
end

--- @param attributes table see BaseItem.fillable for accepted keys
--- @param bindingKey string|nil if given, upserts an item_bindings row
---   pointing that key at the newly created item — the admin-panel
---   equivalent of a plugin calling ItemService.registerRequirements and an
---   operator hand-writing the item_bindings row. Does not check whether
---   any plugin has actually registered bindingKey as required; binding()
---   itself already warns on an unrequired key, that check doesn't need
---   duplicating here.
--- @return number|nil id, string|nil reason
function ItemService.createBaseItem(attributes, bindingKey)
    if not attributes.name or attributes.name == '' then
        return nil, 'Name is required'
    end

    -- "Can be taken" always implies "Can be traded" — see updateBaseItem's
    -- matching enforcement.
    if isTruthyFlag(attributes.is_takeable) then
        attributes.is_giveable = true
    end

    local ok, result = pcall(function() return BaseItem:create(attributes) end)
    if not ok then
        return nil, 'Name already in use'
    end
    local id = result.attributes.id

    if bindingKey then
        upsertBinding(bindingKey, id)
    end

    return id, nil
end

--- @param source number target player to give the item to
--- @param baseItemId number
--- @param amount number
--- @return boolean, string|nil reason
function ItemService.giveToPlayer(source, baseItemId, amount)
    local base = BaseItem:find(baseItemId)
    if not base then
        return false, 'Item not found'
    end
    return ItemService.add(source, base.attributes, amount)
end

--- @return table[] every registered action (the `actions` table), for the
---   admin panel's action picker
function ItemService.listAvailableActions()
    return QueryBuilder.new('actions'):get()
end

--- Whitelist-replaces a base item's `actions` pipeline (the json column
--- EDITABLE_BASE_ITEM_FIELDS/updateBaseItem intentionally excludes, since
--- it's config-shaped rather than admin-panel-shaped for most fields — this
--- is a separate, narrowly-scoped write path just for the admin's Actions
--- editor). Entries referencing an action_id not present in the `actions`
--- table are skipped rather than rejecting the whole write.
--- @param baseItemId number
--- @param actions table[] full replacement array of { action_id, data }
--- @return boolean
function ItemService.setBaseItemActions(baseItemId, actions)
    local valid = {}
    for _, entry in ipairs(actions or {}) do
        local exists = QueryBuilder.new('actions'):where('id', entry.action_id):first()
        if exists then
            table.insert(valid, { action_id = entry.action_id, data = entry.data or {} })
        else
            print('[ItemService] WARNING: setBaseItemActions: skipping unknown action db id ' .. tostring(entry.action_id))
        end
    end
    QueryBuilder.new('base_items'):where('id', baseItemId):update({ actions = valid })
    return true
end

return ItemService
