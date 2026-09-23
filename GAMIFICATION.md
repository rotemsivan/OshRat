# Gamification — עכבר עו״ש (OshRat)

Plan for the XP / mascot-customization system. All of it is **local** (no backend),
CloudKit-syncable later, and separate from the free/Pro split.

## Guiding principles

- **Reward the right behavior**, not raw app-opening: logging, consistency, saving — not
  just launching the app.
- **Cap farmable actions** so XP can't be gamed (e.g. a daily cap on XP from logging).
- **Stay positive**: never punish gaps or nag. Missing a day resets a streak but never
  removes earned XP. Anxiety is the enemy in a finance app.
- **XP unlocks are cosmetic and free.** They are earned by using the app well and are
  completely separate from paid Pro features. Never gate real finance functionality behind
  XP — only mascot cosmetics and badges.
- Keep all tunable numbers (XP values, caps, level curve) in **one config file** so
  balancing is a one-place change.

## 1. How XP is earned (amounts illustrative — keep tunable)

- **Usage:** small XP per transaction logged, with a **daily cap**; a little for updating an
  account balance (rewards keeping data current), also capped.
- **Consistency:** a daily logging/opening **streak**, with milestone bonuses at 7 / 30 / 100
  days.
- **Responsible behavior:** XP for contributing to a goal; a bigger bonus for completing one;
  a monthly bonus for staying within a budget category; emergency-fund milestones.
- **One-time setup:** completing profile, first account, first budget, first goal — front-loads
  early wins so it feels rewarding immediately.

## 2. Levels

Cumulative XP maps to a level via a gently rising curve (each level needs a bit more than the
last). Store **total XP**, derive the level from it. Levels are the main "unlock clock."

## 3. Unlocks & achievements (all cosmetic)

- **Levels** unlock cosmetic **items** for the mascot (hats, outfits, accessories, backgrounds).
- **Achievements** award **patches / medals** for discrete milestones ("first ₪1,000 saved",
  "30-day streak", "3 months under budget", "first goal completed").

## 4. Data model additions (local; CloudKit-syncable later)

- `UserProgress` (one instance): `totalXP`, `currentStreak`, `longestStreak`, `lastActivityDate`.
- Unlocked achievements and unlocked items stored as **sets of string keys**.
- `MascotConfig`: the equipped item key per slot (hat, outfit, accessory, background).
- The **catalogs** — every item and achievement, with unlock rules and XP values — live in
  **code as constants**, NOT the database. Persist only the user's progress, unlocks, and
  equipped choices. This makes adding items later safe and simple.

## 5. The XP engine

A single `ProgressService` with:
- `award(_ amount:reason:)`
- `recordActivity()` — updates the streak
- `checkAchievements()`
- level-unlock logic

Call it from the **existing data-write points** (after adding a transaction, updating a
balance, contributing to a goal) — centralized, not scattered. It enforces the daily caps and
returns "events" (leveled up, achievement unlocked) so the UI can celebrate.

## 6. Reward moments (where the mascot earns its keep)

- **Level-up** → thumbs-up mascot + a brief toast.
- **Achievement** → present/point mascot + the patch revealing.
- **Dashboard** → a streak indicator and a progress bar to the next level.
- Keep celebrations short and calm.

## 7. Mascot customization — technical design

**One design, two sizes.** Build the mascot once as a layered vector; render the same thing
small (~80pt) on the dashboard and large (~300pt) on the wardrobe screen via `.frame`. Vector
stays crisp at both. The small one is a button that opens the wardrobe.

**Layered SVG composed at runtime.** SwiftUI doesn't compose one SVG's parts at runtime, so:
- Author each piece as its own SVG, import each as its own asset with **Preserve Vector Data**.
- Render the mascot as a `ZStack` of `Image` layers, one per slot.

**The rule that makes it work:** every layer is drawn on the **same canvas / viewBox**
(e.g. the full-body `360×660`), positioned exactly where it sits on the body, with everything
else transparent. Shared coordinates → the layers register perfectly when stacked.

**Slots & z-order** (back to front):
```
background  →  base body  →  outfit  →  hat  →  accessory (front)
```
Each slot shows at most one equipped item (or nothing).

**Where the art lives** (`OshRat/Assets.xcassets`, folder groups, **no namespace** — names stay flat):
```
Mascots/Classic/Poses/   rat-mascot-{wave,coin,point,present,thumbsup}          (400×520 bust)
Mascots/Classic/Rig/     rat-part-{head,body,tail,leg-left,leg-right}, rat-fullbody-*  (360×660)
Mascots/Bare/Poses/      bare-bust-{base,wave,present,thumbsup}                 (400×520 bust)
Mascots/Bare/Rig/        bare-fullbody-{base,wave,confident,thumbsup,cheer}     (360×660)
Accessories/Hats/  Accessories/Outfits/  Accessories/Props/  Accessories/Backgrounds/
```
The subfolder says which canvas: `Poses/` is the 400×520 bust crop for spot art, `Rig/` is the
360×660 full body every wardrobe layer is drawn against. A further character or style is a new
folder beside these with its own name prefix; `Props` is the front *accessory* slot. Because
names are flat they must be unique catalog-wide, and an item's folder can change without
touching code or its catalog key.

**`Bare` is the wardrobe base** — the hatless, suitless body this phase needs, already on the
shared canvas, so the re-cut art task below is mostly done for it. Its poses differ **only in
one arm**: the skull, both ears, torso, legs, feet and tail sit at identical coordinates in all
five (33–35 of 37 drawing elements are byte-identical to `bare-fullbody-base`). Consequences
for the art:
- a **hat, glasses or background** drawn once registers on every pose — draw it against
  `bare-fullbody-base` and it fits the rest for free;
- a **sleeved outfit** does not, since one sleeve has to follow the moving arm. Either keep
  outfits torso-only, or cut the sleeve as a per-pose layer.
- the bust is a **different viewport onto the same coordinates**, not a redrawing: the ears sit
  at `cx=152/248 cy=108 r=42` and the skull path starts `M150 98 L250 98 …` in *both*
  `bare-fullbody-*` and `bare-bust-*`. Only the viewBox differs (`0 0 360 660` vs `0 0 400 520`).
  SwiftUI scales each `Image` to its own frame, so a 360×660 hat overlaid on a 400×520 bust
  still misregisters — **but** making the bust variant is a one-line edit: copy the hat SVG and
  change its viewBox. No repositioning, no redrawing.

**Naming convention** (asset name = catalog key):
the classic rat keeps its `rat-` prefix; wardrobe items are
`item-hat-bonnet`, `item-hat-tophat`, `item-outfit-navysuit`,
`item-accessory-glasses`, `item-bg-gold`, …

**Rarity** is a field on the catalog entry in code, not a folder — it gets re-tuned during
balancing, while an item's slot never changes.

**Extensibility:** adding an item later = one new SVG on the shared canvas + one catalog entry.
No change to the rendering code.

**Art task (when this phase starts):** re-cut the existing mascot into a **hatless swappable
base** + separate hat / suit layers on the shared canvas, then design new items the same way.
Concretely: `rat-part-body` currently paints the navy suit (three `url(#suit)` fills) straight
onto the body, so today's `Rig/` is an animation rig, not a swappable base — the outfit slot
can't show anything until those fills move out into their own layer.

**Wardrobe screen:** large live mascot preview at top; below it, sections per slot (Hats,
Outfits, Accessories, Backgrounds) as grids; locked items greyed with an unlock hint; tapping an
unlocked item updates `MascotConfig` and the preview re-renders live. An achievements shelf
shows earned patches/medals.

## 8. Phased build plan (each phase ships on its own)

1. ~~**XP core** — `UserProgress` + engine + a few XP sources (logging, setup milestones) +
   levels + a level-up toast + a streak on the dashboard. No cosmetics yet.~~ **Built.**
   `Models/XPRules.swift` (the one config file, unit-tested), `Models/UserProgress.swift`,
   `Services/ProgressService.swift`, `Views/Gamification/`. Sources wired up: logging a
   transaction (5, capped), correcting a balance (3, capped), the setup milestones (30 each)
   and streak bonuses at 7/30/100. Daily cap 30, shared across the farmable actions. Level
   curve: 100 XP to level 2, each level 50 more than the last. See CLAUDE.md's *Gamification*
   section for how the pieces fit; the rest of this file is still the plan of record.
2. **Achievements** — the catalog + patches/medals + an achievements screen. Two slots are
   already reserved and waiting: the **achievements shelf** on the profile tab (built, drawn as
   empty dashed slots) and `LevelProgressCard`'s **top-trailing pill**, which becomes the *most
   recently earned* achievement. The streak currently sits in that pill as a stand-in — its
   permanent home is the profile's stats row, so phase 2 replaces the pill rather than moving
   the streak anywhere.
3. **Mascot customization** — layered mascot rendering + wardrobe screen + a first item set
   (this is where the mascot is re-cut into layers).
4. **Polish** — more items, haptics/animation, optional Home-Screen widget (streak/level).

## 9. Guardrails recap

Cosmetic-only unlocks · daily caps on farmable actions · never punish or nag · all tunable
numbers in one config · always show the user *why* XP was earned. Fully local — no backend, no
effect on the free/Pro split. It just makes the free app feel alive.
