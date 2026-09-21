# 0002 Energy bar

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
