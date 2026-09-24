# oblsk_items

Item catalog (`base_items`) and per-instance inventory items (`items`) for the Obelisk framework. Loads as part of `core`; restart `core` (or the whole server) to pick up changes.

See [Item module design](https://github.com/Obelisk-Framework/core/blob/main/docs/superpowers/specs/2026-08-10-item-module-design.md) for the full architecture.

## Item owners

Pass a persisted model implementing `itemOwner()` to `ItemService.add`, `remove`, or `has`. The item module supplies this contract for `Item` and, when present, `Character`; each model declares its stable polymorphic `itemOwnerType` explicitly rather than deriving it from a table name. The existing numeric player-source form remains supported for active-character callers.
