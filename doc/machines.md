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
machines are permanently in a powered state (which is purely an implementation
detail for these machines), but do not perform an action until a mob interacts
with them via the callbacks in the machine's `interact1`/`interact2` fields.

**Powered non-interactive machines.** This includes power stations and the
various "machines" scattered around Laboratory, such as extractors, ore
elevators, etc. These machines are purely for aesthetics and serve no purpose to
the player. (In early versions, the power station was actually responsible for
putting permanently-powered machines into the powered state. This was removed
though as it just created additional unnecessary gameplay complexities, e.g., if
the player accidentally destroyed the power station with a bomb.)

**Powered environmental machines.** Includes lights, braziers, lab doors, and
air purifiers. They are permanently powered, and the player doesn't interact
directly with them, but unlike the previous category they do affect gameplay in
significant ways.
