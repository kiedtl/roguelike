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
stay out of. Since you automatically make a noise when you move more than
`Sneak` times in a row (where `Sneak` is one of your stats), they may also come
to investigate noises you make while moving around. (Your `Sneak` will be
affected by different terrain, like soft carpet or creaky wooden floorboards.)
