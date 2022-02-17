# Malfunctioning objects

A hammer evocable can be used to smash an some objects, breaking it, making
some noise, and causing it to malfunction.  Only the so-called "machines"
(braziers, lights, traps, doors, etc) can be broken -- props, walls, posters,
items and the like cannot be broken.

There are currently two things an object can do when malfunctioning: exploding
and zapping nearby mobs. Both of these can be dangerous to the unprepared, so
you will be prompted for a confirmation if you try to smash an explosive
machine, or an electrocutive machine without rElec+.

An explosive machine will have a small chance each turn to create an explosion,
the radius and power of which is dependent on the object (eXamine the object
for more information). If it does not explode on a single turn, the message
"The broken <obj> hums ominously!" will appear in warning.

An electrocutive machine, on the other hand, will have a chance each turn for
nearby mobs (including you, the player) to be zapped by the broken machine if
they are close enough (eXamine the object to see the radius), giving the
message "The <obj> shoots a spark!". The damage given won't be too painful if
the mob has rElec; if it doesn't, it will usually die with 5-6 sparks.

This mechanic exists to allow you to break a machine and lure a guard into its
strike-zone, potentially softening it up a bit before you move in for the kill.

Note that an engineer will eventually show up to repair any broken machines
about 30 turns after you break it, so don't expect, say, a smashed switching
station to keep a hallway clear forever.

# List of malfunctioning objects

- Switching station (electrocutive; range 3; 10-40 damage; 20 median damage)
- Brazier/light     (electrocutive; range 5;  5-20 damage; 10 median damage)
