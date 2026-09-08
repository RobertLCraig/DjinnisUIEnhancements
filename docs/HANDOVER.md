# HANDOVER: Djinni's UI Enhancements (DUI)

> A World of Warcraft Retail addon holding small, unrelated UI fixes: per-boss target frames, a
> druid Ironfur stack bar, feral combo points, and hiding Auctionator's price tracker under the TSM
> auction view. Read this, then `docs/board/`, before changing anything.

**Stage:** active
**Category:** addon
**Status:** v0.3.0, `Interface: 120100`. **No remote to push to**, which is `WoWAddons#0004`.
**Installed and running in the game.** This is one of the addons in active scope. The combo point
module is deployed but **has never been run in a client**; card `0001` carries the nine checks.
**This is the addon that found the 12.1 secret-values fault.** `RAID_CLASS_COLORS[class]` threw
about ten times a second while a boss frame was up, because 12.1 can return an opaque value for a
compound unit token such as `boss1target`, and a secret may not be used as a table key. That fault
class is why `C:\Dev\WoWAddons\docs\DECISIONS.md` exists in its current form.
_Last updated: 2026-09-08 (feral combo point module added; first offline test in this addon)_

## Goal & success criteria
**No PRD exists, and for this addon that is close to correct**: it is a bag of small fixes rather
than a product with a spec. What follows is read off the `.toc` Notes and the file list.

Goal: hold the small UI fixes that are too small to be their own addon, without any of them
depending on the others.

Success is four separate things, each checked in the game:
- Per-boss target frames show, and do not throw, while a boss frame is up.
- The Ironfur stack bar counts stacks correctly on a druid.
- The combo point display matches the stock bar in cat form, and hides out of it.
- Auctionator's price tracker is hidden while the TSM auction view is open, and returns afterwards.

**The non-goals are unknown and need Rob**, and for a grab-bag addon that matters more than usual:
without one, everything small ends up here.

## Canonical data shape
`DjinnisUIEnhancementsDB`, one account-wide SavedVariables table declared in the `.toc`. **Its shape
lives in `Core.lua` and nowhere else**; there is no `DATA-MODEL.md`, and for five Lua files that is
a reasonable place to leave it.

## Architecture / stack
Lua against the Blizzard Retail API. **No bundled libraries at all** - no `Libs/`, no `embeds.xml` -
which is unusual in this workspace and is why `WoWAddons#0003`'s `libs/` criterion was trivially
satisfied here. `## OptionalDeps: EnhanceQoL, ElvUI, Auctionator_PriceTracker, TradeSkillMaster` are
compatibility declarations, and the last two are what `PriceTrackerTSM.lua` hooks. Six Lua files.

No build step. **Almost every check that matters happens in a live game client, which no agent can
run**, so the one exception is worth knowing about: `tests/` holds plain-Lua harnesses that stub the
WoW API and load a real module file. They cover pure logic only, never anything visual. `tests/` is
in the `pkgmeta.yaml` ignore list, so it never reaches the game folder.

## Key files / structure
- `Core.lua` - load, event wiring and `DjinnisUIEnhancementsDB`.
- `BossTarget.lua` - the per-boss target frames. **This is the file that threw on 12.1 secret
  values**, and the one to read first before touching anything keyed on a unit.
- `IronfurBar.lua` - the druid stack bar.
- `ComboPoints.lua` - feral combo points. Read its secret-value guards before touching any power
  read; the reasoning is in the file's own comments.
- `PriceTrackerTSM.lua` - hooks two third-party addons, so it breaks when either of them changes.
- `EditMode.lua` - Blizzard Edit Mode integration. **BossTarget only.** `IronfurBar` and
  `ComboPoints` are positioned by `/djue ... unlock`, drag, `lock`, not by Edit Mode.
- `deploy.ps1` - this addon owns its own, with its own exclusion list.
- `tests/` - offline harnesses, one per module that has logic worth checking. Not deployed.

## Decisions locked
- **A fix here does not depend on another fix here.** Each file stands alone; that is what lets one
  be pulled out into its own addon later.
- **Never key a table on a unit token's return value without checking it first.** 12.1 secret values
  are the reason, and this addon is where the fault was found. See
  `C:\Dev\WoWAddons\docs\DECISIONS.md`.
- **No bundled libraries.** Keeping it that way is what keeps the addon this small.
- **A power value is guarded twice, not once.** `UnitPower` and `UnitPowerMax` carry
  `SecretWhenUnitPowerRestricted` in 12.1, so `ComboPoints.lua` asks
  `C_Secrets.ShouldUnitPowerBeSecret` first **and** tests the returned value with `issecretvalue`.
  Do not collapse the two: the predicate is a claim about what will happen, `issecretvalue` is the
  only test of what did, and `type()` cannot see a secret at all.
- **Reuse Blizzard's atlas art rather than bundling textures.** `ComboPoints.lua` draws the
  `UF-DruidCP-*` set that `Blizzard_UnitFrame` uses, with a flat-colour fallback if
  `C_Texture.GetAtlasInfo` stops recognising a name. An atlas rename would otherwise draw nothing,
  and an invisible addon reads as a broken one.

## Current state
- Done: four modules, deployed and running. The secret-values fault was found and fixed here, and
  the same fault class has since been hit twice more elsewhere, in the combat log and in
  `UNIT_SPELLCAST_SENT`, so **it is broad, not a boss-frame quirk**, and this addon is not proven
  clear of it on other paths.
- In progress: nothing.
- **Not proven:** `ComboPoints.lua` has run in a client, in and out of combat, and card `0001`
  records what that settled. Four criteria on it are still open, all of them things nobody has sat
  down and tried: shifting out of cat, drag-and-reload persistence, the six-point talent, and a full
  dungeon with no Lua error.
- **A trap for whoever reads `readCombo()` next.** Combo points measured **not** secret in combat on
  2026-09-08, so the two guards look like dead code and are not. `UnitPower` carries
  `SecretWhenUnitPowerRestricted` in the API docs, which is Blizzard's to enforce whenever they
  choose; the measurement is what today's client does, not a promise. Card `0001` has the dump.

## What's next (in order)
**`docs/board/` owns this.** One card is open: `0001` needs an adversarial pass and then Rob at a
live client.

## Blockers / open questions
- **No GitHub remote.** `WoWAddons#0004` is that question, and it covers this repo by name. For an
  addon that is live in the game with no off-machine copy, that is the sharpest gap on this page.
- **`PriceTrackerTSM.lua` hooks addons nobody here controls.** Auctionator or TSM updating is enough
  to break it, and nothing will tell you but the game.

## How to pick up
1. Read this file, then `docs/board/README.md` and any card in `docs/board/`.
2. **Read `C:\Dev\WoWAddons\docs\DECISIONS.md` before anything else in this repository.** Both 12.1
   traps live here: secret values, and `RegisterEvent` being refused silently in a way `pcall` does
   not detect.
3. Deploy from the workspace and never edit the game folder:
   `C:\Dev\WoWAddons\bin\deploy.ps1 -WhatIf -Only DjinnisUIEnhancements`, then the same without
   `-WhatIf`. The dry run is the plan.
4. Check any API against `C:\Dev\WoWAddons\wow-ui-source\`, never from memory. Anything defined only
   under `Blizzard_Deprecated*/` is CVar-gated and is not safe to rely on. **Diffing the API surface
   will not find a secret-values fault**: nothing is removed or resignatured, the return value
   simply changes shape.
5. Run the offline harnesses. They need no game and no framework:
   `lua tests/test_combopoints.lua` prints `14 passed, 0 failed`. `lua` on this machine is 5.4;
   the harness loads the module under either 5.1 or 5.4, and `luac -p <file>.lua` is the quickest
   syntax check for the rest.

## Sibling docs
- Workspace: `C:\Dev\WoWAddons\docs\HANDOVER.md` and `docs\DECISIONS.md`.
- **Gaps:** no `README.md`, no `PRD.md`, no `DATA-MODEL.md`, no `DECISIONS.md`, no `CHANGELOG.md`.

## Branch status
One branch, `master`. No remote, so "unpushed" is not a meaningful count here.

## Session log
**Pointer, not a log.** `git log --format='%ad %s%n%b'` is the narrative;
`C:\Dev\WoWAddons\docs\DECISIONS.md` is the rationale.
