--- ItemCategory Model - groups base_items for catalogue/UI display (e.g.
--- shop category tabs). Purely descriptive, no behavior of its own.
ItemCategory = BaseModel:extend('item_categories')

ItemCategory.primaryKey = 'id'
ItemCategory.timestamps = true

ItemCategory.fillable = { 'name' }

ItemCategory.hidden = {}

return ItemCategory
