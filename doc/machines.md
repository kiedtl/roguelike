# Machines

The term "machines" encompass a wide variety of interactive or non-interactive
objects in Oathbreaker; the term includes doors, recharging machines, power
stations, and many other things. There are several types of machines (this is
purely an implementation detail and shouldn't matter to the player).

**Non-powered interactive machines.** This includes non-LAB doors and traps;
they are automatically "powered" when a monster walks over or into them; while
in the "powered" state, which may last several turns (or a single turn,
depending on the machine), an action may be performed. Opacity, walkability, and
other characteristics of these machines will vary between a powered or unpowered
state.

**Powered interactive machines.** This includes recharging stations. These
machines are put into a "powered" state by the level's power station machine,
but do not perform an action until a mob interacts with them via the callbacks
in the machine's `interact1`/`interact2` fields. The fact that the machine must
be "powered" to perform these interactions should normally be an implementation
detail, unless the level's power station is somehow destroyed. In that case the
player will be unable to interact with the machine until an engineer shows up
and repairs the power station.

**Powered non-interactive machines.** This includes power stations and the
various "machines" scattered around Laboratory and Smithing, such as extractors,
chain presses, ore elevators, etc. These machines are purely for aesthetics and
serve no purpose to the player, although they will be repaired by engineers if
destroyed.

**Powered environmental machines.** Includes lights, braziers, lab doors, and
air purifiers. They are powered by the level's power station, and the player
doesn't interact directly with them, but unlike the previous category they do
affect gameplay in significant ways.
