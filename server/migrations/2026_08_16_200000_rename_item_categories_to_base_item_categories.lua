--- Migration: Rename item_categories -> base_item_categories (and the FK
--- column on base_items) to match BaseItem's naming convention. Done as a
--- new migration rather than editing 2026_08_12_150000/150001 in place,
--- since those may already be applied against a developer's local DB.
--- Schema.renameColumn now safely preserves the column's type on MySQL
--- (see core/server/ORM/Dialects/MySQL.lua's renameColumnSQL fix) so this
--- is a plain rename, no add-copy-drop needed; the FK constraint on
--- item_category_id is unnamed (see Blueprint:constrained()) and both
--- MySQL and Postgres carry an unnamed FK constraint across a column
--- rename automatically.
return {
    up = function()
        Schema.renameTable('item_categories', 'base_item_categories')
        Schema.renameColumn('base_items', 'item_category_id', 'base_item_category_id')

        print('[Migration] Renamed item_categories -> base_item_categories')
    end,

    down = function()
        Schema.renameColumn('base_items', 'base_item_category_id', 'item_category_id')
        Schema.renameTable('base_item_categories', 'item_categories')

        print('[Migration] Reverted base_item_categories -> item_categories')
    end
}
