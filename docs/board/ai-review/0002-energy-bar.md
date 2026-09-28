# 0002 Energy bar

## What I need from you

**Play a feral druid and walk these steps. Deployed; `/reload` if the game is running.**

1. Shift to cat. **Pass:** a yellow bar with a number appears under the combo points, drains as
   you spend energy and refills.
2. Shift to bear. **Pass:** it hides.
3. Fight something in cat. **Pass:** the bar and number keep moving during combat.
4. Esc > Edit Mode. **Pass:** "Djinni's Energy Bar" has a box; it drags and snaps like
   Blizzard's frames; clicking it opens a window with Width, Height and Show, and each applies live.
5. Close Edit Mode, `/reload`. **Pass:** position, size and Show setting are as left.
6. Run a dungeon. **Pass:** no Lua error in BugSack from `DjinnisUIEnhancements`.

**Fail:** write the step number and what you saw as a comment and move the card to `todo/`.

**Why it needs you:** it is all on-screen behaviour in the game client, which no agent can run.

## Ask

Rob, 2026-09-21: "Also add an energy tracker", while working on the combo points in Edit Mode.

## What was built

`EnergyBar.lua`, one module, loaded after `ComboPoints.lua`. A status bar in Blizzard's energy
yellow (`PowerBarColor.ENERGY`) with the number on it, gliding between values
(`Enum.StatusBarInterpolation.ExponentialEaseOut`). Defaults to just under the combo points.

- **Shown** whenever energy is the displayed power (`UnitPowerType`, the same cat-form test
  `ComboPoints.lua` uses). "Always" and "Never" are the other choices.
- **In Edit Mode from day one** (the rule from 2026-09-21): drag, snap, and a settings window with
  Width, Height and Show. No Scale row, for the same reason the combo points lost theirs.
- **No secret guard, on purpose.** `UnitPower` can be secret in 12.1, but `StatusBar:SetValue`,
  `SetMinMaxValues` and `FontString:SetText` all accept secret arguments from addon code
  (`SecretArguments = "AllowedWhenTainted"`). The value is passed straight through and never
  compared or joined, so the bar keeps moving even if energy turns secret, where the combo points
  have to hold their last count. `tests/test_energybar.lua` feeds it a secret that raises on any
  comparison or join: 6 passing.
- Events registered one at a time and checked with `IsEventRegistered`, refusals reported once.

## Acceptance criteria

Only Rob can run these.

- [ ] Log in on a druid. Shift to cat: the bar shows and moves as energy is spent and comes back.
  Shift to bear: it hides.
- [ ] In combat, the bar keeps moving (the secret path, live).
- [ ] Edit Mode: "Djinni's Energy Bar" can be dragged, snaps like Blizzard's frames, and its window
  changes Width, Height and Show. `/reload` keeps all of it.
- [ ] No Lua error in BugSack after a dungeon.

## Comments

**2026-09-29** Adversarial review (unattended agent, not the builder). **Verdict: code holds; only
in-game checks remain, so `human-review/`.** No change to `EnergyBar.lua`.

Attacked:
- **The no-guard claim.** Checked against the generated docs: `StatusBar:SetValue` and
  `SetMinMaxValues` are `SecretArguments = "AllowedWhenTainted"` with `interpolation` marked
  `NeverSecret` (`SimpleStatusBarAPIDocumentation.lua`); `FontString:SetText` is
  `AllowedWhenTainted` (`SimpleFontStringAPIDocumentation.lua`); `Enum.StatusBarInterpolation.
  ExponentialEaseOut` exists (`SimpleStatusBarConstantsDocumentation.lua`). The value from
  `UnitPower` / `UnitPowerMax` goes only into those three calls, never compared, joined or keyed.
  `UnitPowerType` has no secret flag, so the show/hide test is safe in combat. The claim holds.
- **Tests.** `tests/test_energybar.lua` 6 passed. Mutation: changing `text:SetText(value)` to
  `SetText(value .. "")` turns it red ("a secret energy value draws without error").
- **Events.** Four, one at a time after `SetScript`, each checked with `IsEventRegistered`,
  refusal reported once and never retried. `UNIT_DISPLAYPOWER` covers form changes, so dropping
  `UPDATE_SHAPESHIFT_FORM` is fine.
- **Edit Mode** goes through the same `registerPlain` as the combo points; reviewed on `0001`,
  where one fix (`GLOBAL_MOUSE_DOWN` verification) landed that applies here too.
- **Behaviour to know, not a defect:** the module builds for every class, and with "When energy is
  your power" a rogue or monk sees it all the time. That matches the file header's stated intent.

Security: **weakest point** is none in data terms; the bar reads only the player's own power.
**Unchecked:** nothing external enters. **Leaks:** nothing leaves the client.
