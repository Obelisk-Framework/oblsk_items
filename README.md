# oblsk_items

Item catalog (`base_items`) and per-instance inventory items (`items`) for the Obelisk framework. Loads as part of `core`; restart `core` (or the whole server) to pick up changes.

See [Item module design](https://github.com/Obelisk-Framework/core/blob/main/docs/superpowers/specs/2026-08-10-item-module-design.md) for the full architecture.

## Item owners

Pass a persisted model implementing `HasItems` to `ItemService.add`, `remove`, or `has`. Models opt in with a stable polymorphic type, for example `HasItems.apply(Character, 'character')`; type is explicit rather than inferred from the database table name. The existing numeric player-source form remains supported for active-character callers.
