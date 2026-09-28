# 0001 Feral combo points

## What I need from you

**Play a feral druid and walk these steps. Already deployed (v0.6.0 plus the 2026-09-29 Edit Mode
fix); `/reload` if the game is running.** Each step has its own pass.

1. In cat form, shift to bear or caster. **Pass:** the points hide. Shift back: they return.
2. Esc > Edit Mode. **Pass:** "Djinni's Combo Points" has a blue box with three lit points.
3. Drag it with Snap on. **Pass:** Blizzard's snap lines show and it snaps to edges, centre and
   other frames.
4. Click it. **Pass:** the box turns yellow and a settings window opens (Point size, Spacing,
   Show, Claw). Each change applies live.
5. Open the Show dropdown and pick an entry. **Pass:** the window stays open.
6. Click empty screen. **Pass:** the window closes. (If chat instead says "the game refused
   GLOBAL_MOUSE_DOWN", note it here: that is the new fallback working, not a crash.)
7. Click it again, then click a Blizzard frame. **Pass:** ours goes blue, our window closes.
8. Claw dropdown: pick a frame number. **Pass:** the points take the new shape.
9. Close Edit Mode, `/reload`. **Pass:** position, size, spacing and claw are as left.
10. Repeat 2-4 and 9 for "Djinni's Ironfur Bar".
11. Take the talent that raises the cap to 6. **Pass:** a sixth point appears.
12. Run a full dungeon. **Pass:** no Lua error in BugSack from `DjinnisUIEnhancements`.

**Fail:** write the step number and what you saw as a comment and move the card to `todo/`.

**Why it needs you:** all of it is drawn by the game client, which no agent can run.

The old `/djue cp unlock` drag criterion is covered by step 9: Edit Mode replaced unlock as the
way to move it, and both save through the same `ns.savePosition`.

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
- [x] **`/djue cp debug` IN COMBAT.** Two dumps at `inCombat=true lockdown=true`, both
      `powerWouldBeSecret=false readCombo=5 readComboMax=5`. **Combo points on the player are not
      secret in combat**, so the display does not freeze mid-fight. The guard stays anyway; see the
      Comments entry for why.
- [x] All five events `=true`. 12.1 refused none of them.
- [x] `atlasPresent=true`. The `UF-DruidCP-*` names are still live in 12.1 and the flat-colour
      fallback was not used.
- [ ] Shift out of cat. The points hide. Shift back. They return.
- [ ] `/djue cp unlock`, drag it, `/djue cp lock`, `/reload`. It is where it was left.
- [ ] Open Edit Mode (Esc > Edit Mode). "Djinni's Combo Points" shows with a blue box and three
  lit points. Drag it. Click it: a settings window opens (Scale, Point size, Spacing, Show).
  Change each one and watch it apply. The box turns yellow when clicked, like Blizzard's.
  Click a Blizzard frame: ours goes blue and our window closes. Click empty screen: the window
  closes. Pick from the "Show" dropdown: the window must NOT close. Move Scale: the frame grows
  around its centre and does not slide. With Snap on, drag it: Blizzard's snap lines show, and
  it snaps by edge or centre to the grid, the screen centre and other frames, like Blizzard's own
  (borrowed `EditModeSystemMixin` methods + `EditModeMagnetismManager:ApplyMagnetism`; the first
  try, rounding the centre to the grid spacing, did not work in game).
- [ ] The still claw is back (2026-09-21), as a "Claw" dropdown in the settings window: Gems, or
  frame 1 to 20. Rob asked for it there so each frame can be judged live, which the slash-command
  dial of 2026-09-08 made too slow. Pick a frame: three points light in the new shape. Close Edit Mode, `/reload`. It is where it was
  left. Same for "Djinni's Ironfur Bar". Added 2026-09-21 (`EditMode.lua` `registerPlain`).
  First attempt (frame drag only, no overlay) did not move in game.
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

### 2026-09-08, in combat, and the art argument settled

**The combat dump landed.** Two of them, both `inCombat=true lockdown=true`, both
`powerWouldBeSecret=false readCombo=5 readComboMax=5`. So **a player's own combo points are not
secret in combat in 12.1**, and the display does not freeze mid-fight.

**The guard stays, and this measurement is the reason to write down rather than to delete it.**
`SecretWhenUnitPowerRestricted` is on `UnitPower` in the API documentation; what today's client
does is Blizzard's to change in any patch, and the predicate costs one call. A future session
reading "measured not secret" as "the guard is dead code" would be removing the only thing standing
between a patch note and a frozen bar. Also confirmed the same run: `slashAtlas=true clawAnim=true`,
so `CreateAnimation("FlipBook")` is the right type string and the inference held.

**The art went one round and came back.** Rob expected a claw that fills up, so a still claw was cut
out of one frame of the slash sheet and put behind `/djue cp claw <0..20>`. He tried frames 1, 10,
11, 12, 14, 15 and 20 and rejected all of them: a frame of a motion-blurred swipe does not read as a
claw at rest. **Reverted in full** (`git revert 85d889b`), and the gems plus the swipe on gain are
what ships. `board/discarded/` was not used because the card as a whole was not abandoned, only one
attempt inside it.

The lesson worth keeping: **an art option that cannot be rendered outside the client cannot be
chosen outside the client either.** Handing Rob a dial was the right shape for the question, and the
answer was no.

An adversarial review still owes an entry here, including the three security questions from the
board README, before this card leaves `ai-review/`.

### 2026-09-29, adversarial review (unattended agent, not the builder)

**Verdict: code holds after one fix; only in-game checks remain, so `human-review/`.**

Attacked:
- **Tests.** `tests/test_combopoints.lua` 26 passed. Mutation: deleting both guards in
  `readCombo()` turns it red ("holds the last known count while secret -- got 0"). It has teeth.
- **Secret values.** `readCombo` / `readComboMax` ask `C_Secrets.ShouldUnitPower(Max)BeSecret` then
  `issecretvalue`, before any `tonumber` or comparison; both predicates are in
  `SecretPredicateAPIDocumentation.lua`. `UnitPowerType` carries no secret flag in
  `UnitDocumentation.lua`, so the cat test is safe in combat. No unit name, GUID or string from the
  game is compared, joined or used as a key anywhere in `ComboPoints.lua` or `EditMode.lua`.
- **Events.** The five module events: one at a time, after `SetScript`, each checked with
  `IsEventRegistered`, refusal reported once. **Found:** `EditMode.lua`'s settings dialog
  registered `GLOBAL_MOUSE_DOWN` on every `OnShow` with no check, so a refusal would have been
  silent and retried per show (the BearWatch trap). **Fixed** in `fd6c5f0`: checked once, reported
  once, never retried; the dialog still closes on its X, another selection, or leaving Edit Mode.
  No test covers it: `EditMode.lua` needs Blizzard's Edit Mode to load. `luac -p` clean.
- **Edit Mode APIs**, all found in `wow-ui-source` on `live`, none under `Blizzard_Deprecated*`:
  `EditModeManagerFrame` `SetSnapPreviewFrame` / `ClearSnapPreviewFrame` / `IsSnapEnabled` /
  `ClearSelectedSystem` / `SelectSystem`, `EditModeMagnetismManager:ApplyMagnetism`, all 21
  borrowed `EditModeSystemMixin` methods (each defined once; `SnapToFrame` needs only
  `self.Selection` and the frame's rect), `EditModeSystemSelectionTemplate` with
  `ShowHighlighted` / `ShowSelected` / `isSelected`, the `EditMode.Enter` / `EditMode.Exit` registry
  events, `MinimalSliderWithSteppersMixin:Init` and its `OnValueChanged` event, `CreateRadio`,
  `Menu.GetManager():IsAnyMenuOpen`, `C_Texture.GetAtlasInfo` fields used by `clawTexCoords`.
- **Rob's rules.** Every frame this addon draws is in Edit Mode (combo points, energy, Ironfur, boss
  targets). The only right-click binding is the boss frames' secure `togglemenu`, which opens a menu.
  A click of any button on an Edit Mode box opens its settings window, as Blizzard's boxes do.

Not proven here: anything visual, the claw crops, snap feel, and whether 12.1 accepts
`GLOBAL_MOUSE_DOWN` (step 6 settles it).

Security: **weakest point** is taint, not data: writing `snapPreviewFrame` into
`EditModeManagerFrame` from addon code is the same thing LibEditMode and EnhanceQoL do, and a
Blizzard change there could make Edit Mode throw `ADDON_ACTION_BLOCKED`; step 12 is where that would
show. **Unchecked:** slash-command input is range-checked (`size`, `gap`, `scale`, `claw`) before
use. **Leaks:** nothing; no data leaves the client.
