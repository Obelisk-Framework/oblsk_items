# oblsk_items

Item catalog (`base_items`) and per-instance inventory items (`items`) for the Obelisk framework. Loads as part of `core`; restart `core` (or the whole server) to pick up changes.

See [Item module design](https://github.com/Obelisk-Framework/core/blob/main/docs/superpowers/specs/2026-08-10-item-module-design.md) for the full architecture.

## Item owners

Pass a persisted model implementing `itemOwner()` to `ItemService.add`, `remove`, or `has`. `Item` uses the module's `HasItems` trait; other modules can implement `itemOwner()` directly. The returned polymorphic type is explicit and stable, never inferred from a table name. Existing numeric player-source calls remain supported for active-character callers.
