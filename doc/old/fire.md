# Fire mechanic

Fire can be caused by a variety of sources, but mostly it'll be due to your
terrorism spree^W^W fights with dungeon foes.

Once a tile is set alight, it will burn for a certain period of turns,
determined by how "flammable" the tile is. While burning, the fire may spread to
neighboring tiles (especially if those neighboring tiles are flammable).

A tile is flammable when:
- A mob without rFire∞ (fire immunity) is standing on it
- An object (not an item) is on it
- Flammable terrain (e.g. wood) is on that tile.

In addition to flammable terrain, there is also fire retardant terrain that puts
out fires (such as shallow water).

To get a rough idea of how many turns are left for a tile to burn, see the tile
glyph:
- `,` (comma): 3 (or fewer) turns. (At this point, the fire is safe to walk on.)
- `^` (pointy thing): 7 (or fewer) turns.
- `§` (silcrow): more than 7 turns.

Stepping into fire with a `^` or `§` is always dangerous without fire immunity,
because you then have a good chance to catch fire (the actual chance depends on
how many turns the tile would've continued to burn).

While burning, you will take damage each turn as well as spread fire to the tile
you're standing on.
