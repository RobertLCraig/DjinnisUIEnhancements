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

Every one of these needs a live client. Ticks below are from Rob's own `/djue cp debug` dumps on
2026-09-08 at 02:06 and 02:09, quoted in the Comments entry.

- [x] Log in on a feral druid. Shift to cat. `builtPointFrames=5`, `shouldShow=true`,
      `frameShown=true`.
- [x] Generate and spend points. `readCombo` moved 0 to 5 and `lastCount` followed it exactly.
      **Not compared against the stock bar side by side**, so "no visible lag" is unproven.
- [ ] **`/djue cp debug` IN COMBAT.** Both dumps read `inCombat=false`, so the one path the secret
      guard exists for has still never been exercised. Wanted: `powerWouldBeSecret` and a real
      `readCombo` while `lockdown=true`. If it prints `<secret/unreadable>`, the guard is working
      but the display is frozen mid-fight, and that is the finding this card is really waiting on.
- [x] All five events `=true`. 12.1 refused none of them.
- [x] `atlasPresent=true`. The `UF-DruidCP-*` names are still live in 12.1 and the flat-colour
      fallback was not used.
- [ ] Shift out of cat. The points hide. Shift back. They return.
- [ ] `/djue cp unlock`, drag it, `/djue cp lock`, `/reload`. It is where it was left.
- [ ] Take the talent that raises the cap to 6. A sixth point appears.
- [ ] No Lua error in BugSack after a full dungeon.

## Comments

### 2026-09-08, Rob's client, first run

Two `/djue cp debug` dumps, one at 0 points and one at 5:

```
class=DRUID isDruid=true powerType=3 inCatForm=true
inCombat=false lockdown=false
powerWouldBeSecret=false readCombo=0 readComboMax=5
lastCount=0 maxPoints=5 builtPointFrames=5
events: UNIT_POWER_FREQUENT=true UNIT_MAXPOWER=true UNIT_DISPLAYPOWER=true
        UPDATE_SHAPESHIFT_FORM=true PLAYER_ENTERING_WORLD=true
atlasPresent=true
visibility=cat -> shouldShow=true frameShown=true _unlocked=false
```

The second dump is identical except `readCombo=5 lastCount=5`.

**Three things this settles for the whole workspace, not just this card.**

1. **12.1 refused none of these five events.** `UNIT_POWER_FREQUENT`, `UNIT_MAXPOWER`,
   `UNIT_DISPLAYPOWER`, `UPDATE_SHAPESHIFT_FORM` and `PLAYER_ENTERING_WORLD` all register. Worth
   knowing because the refusal list is otherwise discovered one addon at a time.
2. **The `UF-DruidCP-*` atlas names are still live.** `atlasPresent=true`, so the flat-colour
   fallback in `setArt()` has never fired and remains untested in a client.
3. **`C_Secrets.ShouldUnitPowerBeSecret` exists and answers.** It returned `false` rather than
   erroring or being nil, which is the first confirmation in this workspace that the `C_Secrets`
   predicate namespace is actually callable from an addon.

**What this does NOT settle, and it is the thing that matters.** Both dumps read
`inCombat=false lockdown=false`. Combo points are a combat resource, so the entire reason
`readCombo()` carries two guards is a state neither dump was in. `powerWouldBeSecret=false` out of
combat says nothing about in combat. Until a dump exists with `lockdown=true`, the secret path is
proven only by `tests/test_combopoints.lua`, against a stubbed API, and the module's central claim
is unverified where it counts.

An adversarial review still owes an entry here, including the three security questions from the
board README, before this card leaves `ai-review/`.
