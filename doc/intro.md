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
