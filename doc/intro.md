# Oathbreaker Quickstart

## Keybindings

Basics:
- **qweadzxc** or **hjklyubn** to move.
- **@** to view character info.
- **i** to view inventory.
- **v** to examine the map.
- **'** to swap weapons.
- **,** to pickup an item.
- **s** or **.** to wait a turn.
- Number keys **0123456789** to activate movement patterns.

Other keybindings:
- **A** to activate something you're standing on.
- **M** to view the message log.
- **t** to toggle Auto-wait (which is quite buggy and annoying at present).

## Gameplay

**Sneak around and stay out of sight.** Stealth is 100%
deterministic in Oathbreaker, no kludgy "You have 23% chance to be detected."
You'll either be detected or not. Red tiles == seen by an enemy == bad!

TODO_GIF: hiding in corner while patrol walks right past

TODO_GIF: standing in room as guard walks towards @, then guard spotting player and
moving one step foward to attack.

**Move without making noise to avoid being detected.** To move quietly, you'll
have to rest every few turns. Keep an eye on the green bar on the HUD. When the
green bar fills up, you're making noise.

TODO_GIF: green bar filling up gradually as one moves.

**If you make noise, guards become suspicious.** They'll come to investigate and
leave only when they're satisfied that there was nothing there. Must've been
rats!

TODO_GIF: making noise in dark area, guard in corner comes to investigate

**Stab unaware enemies.** Stabs deal 10x more damage and daze the victim.
Enemies can only be stabbed if they're (a) unaware of you and (b) aren't
investigating a noise.

TODO_GIF: guard moves into corner and looks other way while player hides in
opposite corner. player moves over and stabs guard.

TODO_GIF: row of patrol pass by player. player stabs some of them.

**You can't attack aware enemies.** Instead, you'll swap places with them.

TODO_GIF: running away from guard in corridor, then swapping places with them.

**You automatically attack nearby enemies if you stay still.** "Staying still"
is any action that isn't a movement. Enemies are attacked in clockwise order,
starting with the northmost enemy.

TODO_GIF: getting surrounded by enemies, moving around them, then waiting (and
auto-attacking)

**Release prisoners for maximum commotion!** Or just to distract a mob of angry
guards.

TODO_GIF: chased by group of enemies to cell, unlock cell, bybye

**Use traps and gas vents to your advantage.** Traps (the pointy `^` things)
release poisonous gas through the gas vents (`+`) when stepped on.

TODO_GIF: stepping on paralysis gas trap

Just remember not to get trapped between pockets of expanding gas yourself!

**Use your environment to your advantage.**

- Traps, already mentioned.
- Fountains (`¶`) replenish a portion of your health.
- Drains (`∩`) can be crawled into to speedily escape pursuit. (Beware:
  sometimes the drain will turn out to be a dead end.)
- Capacitor arrays discharge a blast of electricity, instantly vaporizing all
  enemies in view that don't have electricity resistance (rElec). The downside
  is that enemies with rElec won't be harmed.
- Stalker stations do... something secret :^)

**Use your movement patterns!** Movement patterns are your only way of utilising
magic and spellcasting in this game. Together with evocables and consumables,
they are your only reliable way to fight against enemies that you failed to
stab.

By default, you are given a number of movement patterns that appear next to a
number on the HUD. Press the number to activate the pattern, then follow the
instructions in the log.

TODO_GIF: invoking leap pattern and jumping over pool of water.

**Seek out rings to get more movement patterns.** This is akin to finding a
spellbook. Rings are always found in gold enclosures. Each level will have a
single ring.

TODO_GIF: moving across map to a room with ring, walking to ring, equipping it,
opening inventory, and mousing over ring and looking at description.

**Head for the stairs as fast as possible!** Only escape matters -- don't try
wandering around the levels or looking for loot if you don't know where the
stairs are, or can't make a safe retreat to it if you're pursued. If you can
escape to the stairs without fighting enemies, do so.

The only reason to stay on a level and explore the map is to find some
guaranteed loot that you're missing out on, such as rings.

When you ascend a staircase:
- Enemies lose track of you
- You may gain 2 extra HP
- You may also gain a random talent

If you wish, you can also enter optional stairs. These are entirely optional,
and lead to more dangerous levels with stronger foes.
