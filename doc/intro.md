# Intro

*This documentation is very much WIP. If you have questions, please contact the
author at `kiedtl＠tilde.team` (don't copy/paste) or `/msg cot` on
[libera.chat](https://libera.chat).*

Oathbreaker is a stealth-focused roguelike, a game where the main fighting
strategy is not fighting at all. Your health is extremely limited and doesn't
regenerate until you reach a new floor, and most of the weaker enemies can bring
you to a quarter of your health in a single fight. Even the weakest of enemies
can easily draw half the floor onto you when they turn to flee and call for
help, so the few fights you do end up in have to be ended quickly and with
extreme prejudice.

**tl;dr**:
- Stay out of enemy's sight.
- Don't fight if you can help it. Avoid melee as much as possible.
- Don't make noise.
- Use your inventory (e.g. potions) to end fights quickly.
- Use movement patterns to supplement fights.

The only thing that matters in this game is getting off the floor quickly.
You'll be leveraging poisonous potions, toxic gas, drains, other prisoners, and
the like to get out of fights quickly and make a run for it. The occasional
fountain (`¶`) or potion of recuperation can provide some much needed healing;
other than those two sources, healing is very rare and hard to come by.

You start off at the bottom of the Dungeon, working your way up to the top. Once
you leave a floor, you cannot go back. There will be occasional optional
staircases that lead sideways instead of up (`≤`) and that lead to more
dangerous levels; the second optional floor will have a Rune (`ß`) that you can
collect if you wish. (See the [list of branches](branches.md) for more info.)

Unlike other roguelikes, stealth is very deterministic; enemies have a 100%
chance do detect you inside their (smaller) FOV, which you must take care to
stay out of. All creatures have a conical FOV shape, in the direction they're
currently facing. Many monsters will glance around them as they stand still, and
some monsters (such as guards and sentinels) will occasionally wander off to
another room to guard. While you'll need to stay agile and aware of your
surroundings to avoid acquiring negative health syndrome, the deterministic
stealth system ensures that it's *always* your fault, and not the RNG's, when
you inevitably get caught.

Since you automatically make a noise when you move more than `Sneak` times in a
row (where `Sneak` is one of your stats), they may also come to investigate
noises you make while moving around. (Your `Sneak` will be affected by different
terrain, like soft carpet or creaky wooden floorboards.) While you'll have the
luxury of being able to stay silent much of the time, you'll often have to make
a dash for it when being chased or when trying to stay out of vision. (Of
course, since all of your foes have a `Sneak` value of 1, you'll always be able
to hear them -- as long as they moved in their last turn. A few enemies have the
`Noisy` status, meaning you'll always hear them.)

## Keybindings

- **t** to toggle Auto-wait (which is quite buggy and annoying at present).
- **qweadzxc** or **hjklyubn** to move.
- **@** to view character info.
- **i** to view inventory.
- **v** to examine the map.
- **'** to swap weapons.
- **,** to pickup an item.
- **s** or **.** to wait a turn.
- **A** to activate something you're standing on.
