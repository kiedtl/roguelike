# Statuses

Statuses are any effects, good or bad, that are applied for a specific duration
by an attack or spell, a piece of equipment, or terrain.

Statuses can have a `<Tmp>` duration which lasts for several turns, a `<Prm>`
duration which lasts the entire game, a `<Equ>` duration that lasts until the
equipment giving the status is unequipped, or a `<Ctx>` contextual duration
which lasts until the terrain inflicting the status is removed.

For example, the Dispel Undead item gives you the `<Equ> torment undead` status,
which causes adjacent undead to periodically take damage. Similarly, a potion of
invigoration grants the `<Tmp> invigorated` status, which boosts your fighting
and dodging skills.

## amnesia

Causes a monster to forget any noise or enemies they ran across, and return to a
working state. When the status is depleted, all dementia will be instantly
cured.

## blind

Reduces sight vision to 1, so that monsters/you can only see adjacent tiles.
Very useful for throwing off pursuers, assuming there is already a few tiles of
distance between.

## burning

You are on fire.

- You have a 33% chance to take damage each turn.
- You spread fire to the tile you are on, if it isn't already on fire.

See [fire.md](fire.md) for more details.

## charged

(Monster-only.) When this monster dies, it will violently explode in a blast of
electricity.

## conductive

Causes you to share electric damage with nearby mobs. If those monsters are
conductive as well, the electric arc will propagate through them and into
monsters adjacent to them as well. (Only full rElec will prevent it from
propagating).

Conductivity is typically caused by certain terrain, such as metal floors or
shallow water.

## copper

A `<Ctx>` status given by copper terrain, that enables you to do +3 more
damage(!!) *provided you are wielding a copper weapon*.

## corrupted

A status inflicted by staying near undead.

It has a variety of positive (and, in future releases, negative) effects, such
as preventing enemies inflicting bonus damage to you with bone weapons, as well
as revealing the locations of all undead on the map.

The main negative effect of corruption is that it instantly alerts the undead
which inflicted it of your presence. This means that attempting to sneak past
unaware or dormant undead could potentially fail catastrophically if you stay
next to them too long.

In future releases, additional negative effects will be added.

## dazed

Causes all attempts at moving to fail, moving in a random direction instead.

## debilitated

Confers a hefty penalty to your `melee%` and `evade%` stats.

## detect electricity

Causes the player to passively detect certain tiles, such as ones that have
certain monsters on them (like sparklings, sulfur fiends, and spires), and a few
other dungeon features.

Depending on your playstyle, it may synergize well with a build that is
vulnerable to electricity, as it allows you to detect common
electricity-damaging monsters and avoid them more easily.

## detect heat

Causes the player to passively detect sources of heat, such as braziers,
perpetually burning monsters (e.g. emberlings, cinder worms, and burning
brutes), tiles that are currently on fire, and a few other dungeon features.

Depending on your playstyle, it may synergize well with a build that is
vulnerable to fire, as it allows you to detect common fire-damaging monsters and
avoid them more easily.

## disoriented

Prevents diagonal movement and diagonal attacks.

## dormant

See `sleeping`.

## drunk

Causes any attempt to move to fail, resulting in erratic movement in a random
adjacent direction.

For example, if a drunk monster attempts to move north, they may move either
northwest or northeast instead (but only if those tiles are passable).

Drunk monsters are typically encountered in Tavern treasure vaults.

## echolocating

When you hear a noise, you will passively map out the areas near that sound.

(No dungeon features etc. will be detected, just whether the tile is a floor or
a wall.)

## enraged

- +20% chance to land a hit.
- -10% chance to dodge an attack.
- +20% damage for melee hits.

## exhausted

(Monster-only.) The monster is exhausted, and the status that usually triggers
when they flee (e.g. `hasted` or `enraged`) won't have any effect.

## explosive

(Monster-only.) When this monster dies, it will violently explode.

## fireproof

- +25% fire resistance.

## flammable

- -25% fire resistance.

## glowing

You emit light.

Not exactly the best status to have if you're trying to hide from guards in dark
areas.

## hasted

You are faster than usual.

While you have this status, many movement patterns may be harder or outright
impossible to use, unfortunately. For that reason, it's best to consider sources
of this status purely as escape items. (In a future release, this status might
be removed entirely to mitigate this issue.)

## held

Causes all attempts to move to fail with the message "You flail around
helplessly." Attempting to move will, however, cause the duration of the status
to decrease faster.

## insane

(Monster-only.) Causes the monster in question to become hostile to every other
monster, including former allies and other insane monsters.

## intimidating

Sharply reduces all enemies' morale (the ones that can see you), making it much
more likely that they'll flee.

## invigorated

- You have a bonus to your evasion.
- You deal extra damage in melee.

## lifespan

(Monster-only.) When this status runs out, the monster will die or
self-destruct. Usually found paired with the `explosive` or `charged` statuses.

## nauseated

You are unable to drink potions.

Doesn't affect enemies, since they don't drink potions at any rate.

## night-vision

Usually found on monsters. Indicates that they can see in dark tiles.

(The player has innate night-vision, thus making this status meaningless for the
player.)

## noisy

Causes noise to be emit on each turn, regardless if the mob is moving or not.

Many monsters have this status, allowing you to detect them more easily.

## pain

- You are in agony and cannot rest.
- You take variable amounts of damage each turn. (For now that amount is
  dependent on the source of this status; in future releases this will be
  properly documented.)

## paralyzed

Causes you to skip your turn.

## recuperating

- You regenerate 1 HP per turn.
- Your Armor is lowered by 25%.

## riposte

An effect (notably given by rapiers) that allow you to retaliate after a blocked
attack, executing a free attack.

## sleeping / dormant

Occasionally monsters will be spawned asleep; in other circumstances you may be
able to put them to sleep. Undead or otherwise nonliving monsters will be shown
as "dormant" in this stage, instead of "sleeping".

A sleeping monster will wake up:
- when you attack them (or try to)
- when a nearby ally informs them of your presence
- if the monster isn't deaf and it hears a noise

## slowed

Your movements, attacks, and other actions are all much slower than usual. A
fairly rare status, one which will probably be removed in future versions
because it makes it much harder to execute movement patterns.

## terrified

No effect on the player.

For monsters, makes it drastically more likely that they'll flee from you
(unless they're fearless, undead, or non-living).
