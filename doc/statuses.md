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

## blind

Reduces sight vision to 1, so that monsters/you can only see adjacent tiles.
Very useful for throwing off pursuers, assuming there is already a few tiles of
distance between.

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
unaware or dormant undead could potentially fail catastrophically if the RNG
decides to screw with you.

In future releases, additional negative effects will be added.

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

## dormant

See `sleeping`.

## drunk

Causes any attempt to move to fail, resulting in erratic movement in a random
adjacent direction.

For example, if a drunk monster attempts to move north, they may move either
northwest or northeast instead (but only if those tiles are passable).

Drunk monsters are typically encountered in Tavern treasure vaults.

## enraged

- +20% chance to land a hit.
- -10% chance to dodge an attack.
- +20% damage for melee hits.
- +20% speed bonus.

## fireproof

- +25% fire resistance.

## flammable

- -25% fire resistance.

## intimidating

Sharply reduces all enemies' morale (the ones that can see you), making it much
more likely that they'll flee.

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
