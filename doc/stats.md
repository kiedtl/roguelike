# Stats and resistances

## Melee%

The chance you have to land a melee attack. (Doesn't take into account the
enemy's evasion.)

Set to 60% by default.

## Missile%

The chance for a thrown missile to land on its target. (Doesn't take into
account the enemy's evasion.)

Set to 60% by default for the player (40% for most other monsters).

## Evade%

Your chance to dodge.

The player has 10% evasion by default.

Your evasion is increased by:
- Being `invigorated`.
- Being in an open area.
- Staying in dark tiles.

You evasion is reduced by:
- Being `enraged`, `held`, or `debilitated`.

## Martial

Determines the maximum number of times the player/monster can attack in a single turn if
they're wielding a martial weapon. So if a martial weapon (e.g. a dagger) is
being wielded and the `Martial` stat is 4, up to 4 consecutive attacks can be
carried out assuming they all strike their target (a missed or dodged attack
cancels the martial series).

This mechanic is very similar to the one in TGGW, so if you've played that game,
there's a good chance you understand this mechanic as well.

## Sneak

Controls how many times the player can move consecutively before needing to rest
to avoid making noise.

For the player, this is 4 by default; for monsters, it's 0 (so they make noise
every turn they move).

## Vision

The radius of your FOV. Certain terrain features (e.g. platforms) increase your
Vision.

## Willpower

In a range of 0 to 10. Controls your ability to resist hostile enchantments, as
well as force your enchantments on others. You cannot be affected by a monster
with a lower willpower than you, and vice versa.

## Spikes

The `Spikes` stat is the number of "retaliation" damage you inflict on enemies
when they attack you and score a hit.

This stat is normally 0, but with enough luck one can find enough
`Spike`-increasing items (such as spiked bucklers and spiked leather armor) to
increase it to 3.

## rFire

Fire resistance.

Sources:
- Cloak of silicon
- Potion of fortification

## rElec

Electricity resistance.

Sources:
- Cloak of fur
- Potion of fortification

## Armor

Resistance to any physical damage (from a weapon, a spell, explosions, etc).

Sources:
- ¡recuperate (-25% Armor)
- Any armor.

## rFume

This resistance, which is always positive, provides a chance to not receive the
effects of a gas when standing in it. 20% rFume is 20% for the gas to not have
an effect, etc.

Sources: none currently.

Monsters:
- Statues (100%)
