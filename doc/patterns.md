# Movement patterns

There are two types of movement patterns: one which are given you you at the
start of the game, and those which are acquired from rings.

## Initial (non-ring) movement patterns

**Pin foe**:

Pattern: attack a foe, move diagonally around it, attack it again, then move
away.

```
.....                  .....                  ......
..m..    <attack m>    ..m@.    <attack m>    ..m.@.
..@..                  .....                  ......

                       <move>                 <move>
```

Effect: `held` status for a few turns, enough to set up a charge or a lunge.

**Charge**:

Pattern: step away from a foe, wait, step against foe.

```
.....    ..@..    ..@..    .....
..@..    .....    .....    ..@..
.....    .....    ..m..    ..m..
.....    ..m..    .....    .....
..m..    .....    .....    .....

         <move>   <wait>   <move>
```

Effect: Foe is knocked back 7 tiles.

**Lunge**:

Pattern: wait, move forward against foe.

```
.@.    ..@..    .....
...    .....    ..@..
...    ..m..    ..m..
.m.    .....    .....

       <wait>   <move>
```

Effect: You get a free attack against that foe which does triple damage and
never misses, and the foe gets the `Fear` status for 7 turns.

**Eyepunch**:

Pattern: move twice near the enemy you're going to attack, then attack.

```
......     ......     ......
......     ......     ......
..m@..     ..m...     ..m...     <attack m>
......     ...@..     ..@...
......     ......     ......

           <move>     <move>
```

Effect: a few turns of blindness, and ~10 turns of disorientation. The idea is
that you punch a guard in the eye in a large-ish room, then move away diagonally
to gain distance quickly.

**Leap**:

Pattern: step adjacent to a wall and wait twice.

```
#....    #....    #....    #....
#.@..    #@...    #@...    #@...
#....    #....    #....    #....
#....    #....    #....    #....

         <move>   <rest>   <rest>
```

Effect: You are launched 7 tiles in the direction opposite to your first
movement's direction.
