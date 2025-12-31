<img style="align:center" src="https://tilde.team/~kiedtl/images/rl/showcase/title.png" alt="Oathbreaker" />

Oathbreaker is a coffeebreak roguelike focused on stealth. You are a prisoner in
a goblin outpost, and must escape before your impending execution.

Your health is extremely limited and doesn't regenerate until you find healing
items, and most of the enemies can bring you to a quarter of your health in just
a few fights. Even the weakest of enemies could potentially draw half the floor
onto you if they escape and call for help, so the few fights you do end up in
have to be ended quickly and with extreme prejudice.

![screenshot](https://tilde.team/~kiedtl/images/rl/showcase/bad-situation.png)

[Here's](https://tilde.team/~kiedtl/blog/roguelike) the (very outdated) initial
writeup back when I started the project in May 2021.

*Inspecting a lead turtle:*

![inspecting monsters](https://tilde.team/~kiedtl/images/rl/showcase/lead-turtle.png)

*Speedrunning a death in one of the early levels, for demonstration
purposes.

![GIF](https://tilde.team/~kiedtl/images/rl/showcase/demonstration.gif)

## Gameplay

The game includes a brief guide in the title screen. Other questions can be
answered at:

- The [Discord](https://discord.gg/tUhUHffRCr)
- `#oathbreaker` on Libera
- The author's email at `$GITHUB_USERNAME @ tilde |dot| team`.

## Installation

Head over to the Releases and grab a binary. Please note that macOS is not
supported.

### Building from source

NOTE: Building *on* Windows is not possible, at least not without heavy
modifications. Building *for* Windows is supported.

To build from source, you'll need at least the following prerequisites:

- [zig](https://ziglang.org/)
- [just](https://github.com/casey/just)

If building for Windows, you'll also to retrieve the Mingw packages
with `tools/retrieve-mingw.sh`. A brain may be required for this step.

Then:

- Pull in third party submodules using `git submodule update --init --recursive`
- Execute `just` in the project root.

The result will be in `zig-out/bin/rl`.

## Contributing

Please discuss with me before submitting a PR.

## License

The game itself is licensed under the GPLv3 license. I may be willing to
relicense certain portions if you wish to use it; contact me for details.

The game's font is derived from [Spleen](https://github.com/fcambus/spleen) by
Frederic Cambus and is licensed under the [BSD 2-clause
license](https://github.com/fcambus/spleen/blob/master/LICENSE).
