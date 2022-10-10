# Gases

**NOTE**: Current, the Examine mode doesn't show what gas is on a tile. You'll
have to figure it out yourself for now (by the color), unfortunately.

Oathbreaker's gases are modelled after Brogue's gas clouds that spread over the
surrounding area, usually at a rate of ~1 tile per turn. They can be created by
lava (smoke), harmful potions, enemy abilities, and other sources.

Unlike Brogue, where you stay away from gas traps except for special
circumstances (e.g. if you have armor of respiration), you are encouraged to use
poisonous gas against foes.

There are a few common sources of gas in-game:
- Gas traps (the pre-placed `^` things), which emit gas through the gas vents
  (`+`) when you step on them. (Enemies won't trigger them.)
- Potions. (Examine the potion and see the `Effect` section on the right pane;
  if the effect is listed as `<Gas> some gas name here`, it's usually meant to
  be thrown at enemies.)

## Paralysis gas

- **Color**: white
- **Sources**: potion of petrification, paralysis gas trap.

Obviously harmful. Will paralyse you for a long time.

## Smoke gas

- **Color**: white
- **Sources**: potion of fog, lava

May not be harmful. Obscures vision; has no other effect.

## Disorienting gas

- **Color**: blue
- **Sources**: potion of disorientation, disorienting gas traps

Harmful. Disorients you, preventing you from moving diagonally.

## Slowing gas

(Currently unused.)

## Healing gas

- **Color**: pink

(Currently unused.)

## Dust

- **Color**: yellow
- **Sources**: some Laboratory machines (rare), dustlings (when hurt).

Obscures vision. When dustlings are hurt, they release this gas instead of
blood.

## Steam

- **Color**: white
- **Sources**: water nearby lava tiles, steam vents (temporarily removed from
  game).

Harmful. Damages you (fire damage).

## Miasma

- **Color**: light purple
- **Sources**: sulfur fiends (attack), bloats (when hurt).

Harmful. Prevents you from drinking potions. When bloats are hurt, they release
miasma instead of blood.

## Seizure gas

- Color: bright yellow
- Sources: potions of debilitation, seizure gas traps.

Harmful. Gives the `debilitated` status, sharply reducing your melee accuracy
and your evasion.

## Tear gas

- Color: light blue
- Sources: potions of irritation, blinding gas traps.

Harmful. Gives the `blind` status, reducing vision range to 1.
