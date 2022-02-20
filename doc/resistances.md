# Resistances

Oathbreaker's resistances system is modelled after DCSS' resistances, with some
simplifications.

There are 6 levels of resistances:
-  -2 `xx`: very vunerable, 50% more damage
-  -1 `x`: vunerable, 25% more damage
-   0 `.`: no resistances
-  +1 `+`: resistant, 50% less damage
-  +2 `++`: very resistant, 75% less damage
- inf `∞`: immune (unaffected)

There are 6 types of resistances:

## rFire

Fire resistance.

Sources:
- Cloak of silicon

## rElec

Electricity resistance.

Sources:
- Cloak of fur

## rMlee

Resistance to any physical damage (from a weapon, a spell, explosions, etc).

Sources: none currently.

Monsters:
- Statues (`rMlee∞`)

## rFume

Resistance to gases.

This resistance works differently from others:
-   0 `.`: no resistance to gases.
-  +1 `+`: 80% chance for a gas' effect to not trigger on a turn.
- inf `∞`: unbreathing, not affected by gases.

Sources: none currently.

Monsters:
- Statues (`rFume∞`)

## rPois

Poison resistance.

Sources: none currently.

## rPara

Resistance to paralysis.

This resistance works differently from others:
-   0  `.`: no resistance to paralysis.
-  +1  `+`: paralysis wears off 1.5 times as fast.
-  +2 `++`: paralysis wears off 2 times as fast.
- inf  `∞`: cannot be paralysed.

Sources: none currently.
