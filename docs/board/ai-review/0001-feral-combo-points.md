# 0001 Feral combo points

## Ask

Rob, 2026-09-08: "Want to make an addon (or find an existing one that works with the current patch)
that tracks feral druid combo points."

Two things already did it and were shown to him first: Blizzard's own `DruidComboPointBar`
(`Blizzard_UnitFrame/Mainline/DruidComboPointBar.lua`), which cannot be skinned, and
`EnhanceQoLResourceBars`, which is installed and does skin (`ResourceBars.lua:6148` lists
`COMBO_POINTS` as separator-eligible; `POWER_TYPE_STYLE_OVERRIDE_KEYS` at line 703 carries texture,
colour, gradient, backdrop and font per power type). Both draw a **segmented bar**.

Rob picked build, for one reason: he wants five discrete claw points, not a bar split into five.
He also said this belongs in `DjinnisUIEnhancements`, which matches the standing decision that a
small fix goes in the grab-bag addon rather than an eleventh folder (workspace `docs/DECISIONS.md`,
2026-08-21).

## Direction

**The art is Blizzard's, not new art.** `DruidComboPointBar.xml` uses a `UF-DruidCP-*` atlas set:
`-BG-Shadow`, `-BG-Dis`, `-BG-Active`, `-Ring-Glow`, `-Icon`. Reusing those means nothing is
bundled, nothing has to be redrawn for a patch, and it already looks like the rest of the UI. What
this module adds over the stock bar is that it is movable, scalable and has its own visibility rule.

## Plan

- [x] Confirm no `Djinnis*` addon already tracks combo points. None does.
- [x] Check the secrecy rules before reading the power value.
- [x] Build it as a module beside `IronfurBar.lua`, wired the same way.
- [x] Offline check for the one thing a client cannot exercise: the secret path.
- [ ] **In-game check. Only Rob can run this.** See the criteria below.

## What was built

`ComboPoints.lua`, one module, plus five lines in `Core.lua` and one in the `.toc`.

Five point frames in a row under a movable container. Each carries the five Blizzard atlas
textures; active swaps `-BG-Dis` for `-BG-Active` and lights `-Ring-Glow`. Event driven, no
`OnUpdate` ticker: `UNIT_POWER_FREQUENT`, `UNIT_MAXPOWER`, `UNIT_DISPLAYPOWER`,
`UPDATE_SHAPESHIFT_FORM`, `PLAYER_ENTERING_WORLD`.

Three decisions worth recording:

- **The combo point count is guarded twice.** `UnitPower` and `UnitPowerMax` carry
  `SecretWhenUnitPowerRestricted` / `SecretWhenUnitPowerMaxRestricted` in 12.1
  (`UnitDocumentation.lua`), so the number they return can be a secret that must not be compared.
  `readCombo()` asks `C_Secrets.ShouldUnitPowerBeSecret("player", ComboPoints)` first and then tests
  the returned value with `issecretvalue`. Both, because `type()` cannot see a secret and the
  up-front predicate is a claim about what will happen rather than what did. When the value is
  secret the display **holds its last known count** rather than guessing or blanking.
- **Cat form is detected with `UnitPowerType`, not `GetShapeshiftFormID`.** This is exactly what
  `DruidComboPointBarMixin:ShouldShowBar` does: a druid whose displayed power is Energy is in cat.
  `UnitPowerType` carries no secret predicate, so it is readable in combat where the power value
  may not be. `IronfurBar.lua` uses the form ID instead and that is fine there; it is not copied
  here because this one has to be right mid-fight.
- **Events are registered one at a time, after `SetScript`, each verified with
  `IsEventRegistered`, and a refusal is reported once and never retried.** Workspace
  `docs/DECISIONS.md`, 2026-08-21 and 2026-09-02.

Also: `setArt()` falls back to flat colour if `C_Texture.GetAtlasInfo` does not know an atlas name.
An atlas rename between patches would otherwise draw nothing, and an invisible addon reads as a
broken one.

## Offline check

`tests/test_combopoints.lua`, plain Lua, no framework, excluded from deploy via `pkgmeta.yaml`:

```
lua tests/test_combopoints.lua        # 14 passed, 0 failed
```

It stubs the WoW API and loads the real module. The fake secret is a table whose `__lt` / `__le` /
`__eq` raise, so if the module ever compares a secret instead of testing it first, the harness fails
with the error the client would have thrown. **The check was mutation-tested**: deleting the two
guards from `readCombo()` turns it red ("holds the last known count while secret -- got 0"), so it
has teeth rather than only passing.

It covers counting 0/1/3/5, the secret path, the three visibility modes, and the non-druid case. It
does **not** cover anything visual, anything about anchoring, or whether the atlases exist.

## Acceptance criteria

Every one of these needs a live client. Nothing here has been run in the game.

- [ ] Log in on a feral druid. Shift to cat. Five claw points appear at screen centre, 200px down.
- [ ] Generate and spend points. The lit count matches the stock bar under the player frame, with
      no visible lag.
- [ ] `/djue cp debug` in combat prints `powerWouldBeSecret=false` and a real `readCombo`. If it
      prints `<secret/unreadable>`, the guard is doing its job but the display is frozen, and that
      is a finding worth writing on this card.
- [ ] `/djue cp debug` shows all five events `=true`. Any `false` means 12.1 refused one.
- [ ] `/djue cp debug` shows `atlasPresent=true`. If false, the art fell back to plain squares and
      the atlas names need re-reading out of `wow-ui-source`.
- [ ] Shift out of cat. The points hide. Shift back. They return.
- [ ] `/djue cp unlock`, drag it, `/djue cp lock`, `/reload`. It is where it was left.
- [ ] Take the talent that raises the cap to 6. A sixth point appears.
- [ ] No Lua error in BugSack after a full dungeon.

## Comments

_(An adversarial review owes an entry here before this card leaves `ai-review/`, including the
three security questions from the board README.)_
