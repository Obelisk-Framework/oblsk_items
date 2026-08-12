--- ItemBinding Model - one row per logical item role ('currency.cash') an
--- admin has assigned to a concrete base_items row. See
--- docs/superpowers/specs/2026-08-12-banking-plugin-design.md §3.
ItemBinding = BaseModel:extend('item_bindings')

ItemBinding.primaryKey = 'id'
ItemBinding.timestamps = false
ItemBinding.fillable = { 'key', 'base_item_id', 'updated_by', 'updated_at' }
ItemBinding.hidden = {}

return ItemBinding
