--- BaseItemCategory Model - groups base_items for catalogue/UI display
--- (e.g. shop category tabs) and declares a typed field schema (see
--- `fields`, added in the next migration) that item editors use to render
--- category-specific data inputs (e.g. medical_description for a
--- medication category). Renamed from ItemCategory to match BaseItem's
--- naming convention — see
--- the BaseItemCategory design spec (obelisk-framework repo,
--- docs/superpowers/specs/2026-08-16-base-item-category-fields-and-respawn-flag-design.md).
BaseItemCategory = BaseModel:extend('base_item_categories')

BaseItemCategory.primaryKey = 'id'
BaseItemCategory.timestamps = true

BaseItemCategory.fillable = { 'name', 'fields' }

BaseItemCategory.casts = {
    fields = 'json',
}

BaseItemCategory.hidden = {}

function BaseItemCategory:baseItems()
    return self:hasMany(BaseItem, 'base_item_category_id', 'id')
end

return BaseItemCategory
