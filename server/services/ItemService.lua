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

return ItemService
