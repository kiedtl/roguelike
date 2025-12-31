// All-in-one file for tutorial, including UI and mapgen stuff.

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const meta = std.meta;

const StackBuffer = @import("buffer.zig").StackBuffer;

const alert = @import("alert.zig");
const colors = @import("colors.zig");
const display = @import("display.zig");
const err = @import("err.zig");
const janet = @import("janet.zig");
const main = @import("main.zig");
const mapgen = @import("mapgen.zig");
const mobs = @import("mobs.zig");
const Mob = types.Mob;
const rng = @import("rng.zig");
const state = @import("state.zig");
const types = @import("types.zig");
const ui = @import("ui.zig");

const Coord = types.Coord;
const DIRECTIONS = types.DIRECTIONS;
const Direction = types.Direction;
const Rect = types.Rect;
const Tile = types.Tile;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const TUTORIAL_LEVEL = LEVELS - 1;

const Section = struct {
    title: []const u8,
    group: []const u8,
    reset_at: usize,
    rate: usize = 600,
    portions: []const Portion,
};

const Portion = struct {
    fab: ?[]const u8,
    view: Rect = Rect{
        .start = Coord{
            .x = 0,
            .y = 0,
            .z = TUTORIAL_LEVEL,
        },
        .width = 10,
        .height = 10,
    },
    text: []const u8,
};

const SECTIONS = &[_]Section{
    Section{
        .title = "Field of View",
        .group = "BASICS",
        .reset_at = 25,
        .portions = &[_]Portion{
            Portion{
                .fab = "TUT_fov",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 0), 10, 10),
                .text =
                \\
                \\ The field of view of enemies is marked with squares.
                \\
                \\ If you're in the field of vision $cwhen the enemy takes their turn$., you
                \\ will $ralways$. be spotted.
                \\
                \\ (If you step in and out of an enemy's FoV before they take their turn,
                \\ that won't happen.)
                ,
            },
            Portion{
                .fab = "TUT_fov2",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 14), 10, 10),
                .text =
                \\
                \\
                \\
                \\ At it's core, Oathbreaker is about avoiding detection as much as possible.
                \\
                \\ Individual fights are often winnable, but trying to clear a floor is a great
                \\ way to quickly lose.
                ,
            },
        },
    },
    Section{
        .title = "Lighting",
        .group = "BASICS",
        .reset_at = 10,
        .portions = &[_]Portion{
            Portion{
                .fab = "TUT_lighting",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 0), 10, 10),
                .text =
                \\
                \\
                \\
                \\ Lights, like the lamp or electric brazier, create light areas in which you
                \\ can be seen.
                \\
                \\ Other creatures either have or don't have night vision. Those who don't
                \\ cannot see at all in dark areas.
                ,
            },
            Portion{
                .fab = "TUT_lighting2",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 11), 10, 10),
                .text =
                \\
                \\
                \\
                \\
                \\ Keep in mind that a creature can $ralways$. see at least one tile in front of
                \\ them, even if they're in a dark area with no night vision.
                ,
            },
        },
    },

    // Enemies

    Section{
        .title = "Messing Around",
        .group = "ENEMIES & ESCAPE",
        .reset_at = 25,
        .portions = &[_]Portion{
            Portion{
                .fab = "TUT_messing_around",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 0), 10, 10),
                .text =
                \\
                \\
                \\
                \\
                \\ When an enemy sees you, they will switch to combat.
                \\
                \\ For some enemies, this means pursuit...
                ,
            },
            Portion{
                .fab = "TUT_messing_around2",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 11), 10, 10),
                .text =
                \\
                \\
                \\
                \\
                \\ ...for others enemies, it means fleeing and warning their comrades.
                \\
                \\ If time passes and they don't see you, they'll forget you... mostly.
                ,
            },
            Portion{
                .fab = null,
                .text =
                \\
                \\ $gNOTE:$.
                \\ ·    $rRed$. creatures are enemies in $rcombat$..
                \\ · $oYellow$. creatures are suspicous enemies, $oinvestigating$. something.
                \\ ·  $aGreen$. creatures are $anoncombatants$. $g(but still hostile)$..
                \\ ·   $bBlue$. creatures are $bprisoners$., (usually) friendly.
                \\ ·   $pPink$. creatures are $psleeping$..
                \\ ·  $.White$. creatures are either friendly, unaware, dazed, or paralyzed.
                ,
            },
        },
    },
    Section{
        .title = "Finding out",
        .group = "ENEMIES & ESCAPE",
        .reset_at = 15,
        .portions = &[_]Portion{
            Portion{
                .fab = "TUT_finding_out",
                .text =
                \\
                \\
                \\
                \\
                \\
                \\ There are always unpleasant side-effects to creating a disturbance on a floor.
                ,
            },
            Portion{
                .fab = "TUT_finding_out2",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 11), 10, 10),
                .text =
                \\
                \\
                \\
                \\
                \\ It's almost always better to flee to the stairs, rather than lingering and
                \\ drawing attention.
                ,
            },
        },
    },
    Section{
        .title = "Non-combatants",
        .group = "ENEMIES & ESCAPE",
        .reset_at = 90,
        .rate = 200,
        .portions = &[_]Portion{
            Portion{
                .fab = "TUT_noncombats",
                .text =
                \\
                \\
                \\
                \\ Cleaners ($aë$.) and coroners ($aö$.) are summoned when bloodstains or corpses ($p%$.) are found.
                \\ They are $agreen$. and will not fight you, but are $rstill hostile$.!
                \\
                \\ When they see you, they'll flee back to the stairs and warn any friends they meet.
                ,
            },
            Portion{
                .fab = "TUT_noncombats2",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 15), 10, 10),
                .text =
                \\
                \\
                \\
                \\ $gScene:$.
                \\ · A prisoner (p), having killed several guards, is attacked.
                \\ · The guard (g) and executioner (x) kill the prisoner and look around.
                \\ · Each corpse is reported.
                \\ · Cleaners appear to clean the floor.
                \\ · Coroners come to examine the corpses, and potentially request reinforcements.
                ,
            },
            Portion{
                .fab = null,
                .text =
                \\
                \\ $oWarning$.: Each corpse that you leave behind to be noted and examined will
                \\ make the level harder.
                \\
                \\ Initially nothing will happen; then, guards will begin reinforcing chokepoints and 
                \\ important rooms. Sources of magic and other resources will be destroyed. Finally,
                \\ powerful enemies may be sent to track you down.
                ,
            },
        },
    },

    // Magic

    Section{
        .title = "Spellcasting",
        .group = "MAGIC",
        .reset_at = 90,
        .portions = &[_]Portion{
            Portion{
                .fab = "TUT_spellcasting",
                .text =
                \\
                \\ Many creatures you meet use magic and spells for their abilities.
                \\
                \\
                \\ $g(Some spellcasters are marked as being a $oWielder$g. More on this later.)
                ,
            },
            Portion{
                .fab = "TUT_spellcasting2",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 11), 10, 10),
                .text =
                \\
                \\ Since you're a weakling human, you'll need to steal rings ($o*$.) from the
                \\ ground.
                \\
                \\
                \\ Rings give both spells and a small amount of bonus mana. $g(Press $bSPACE$g
                \\ to cast your spells.)$.
                \\
                \\ Each floor will usually have at least one ring.
                ,
            },
        },
    },
    Section{
        .title = "Mana",
        .group = "MAGIC",
        .reset_at = 2,
        .rate = 99999999,
        .portions = &[_]Portion{
            Portion{
                .fab = null,
                .text =
                \\
                \\ All spells (including for enemies) require mana to cast.
                \\
                \\ Your mana does not regenerate, so you need to keep finding mana sources to
                \\ keep a spellcaster build going.
                \\
                \\ Rings give a fixed amount of mana when first picked up, but not enough
                \\ to cast spells often.
                ,
            },
            Portion{
                .fab = "TUT_spellcasting3",
                .text =
                \\
                \\
                \\
                \\ Shrines, however, give much larger amounts of mana.
                \\
                \\ Drawback: they're harder to find and usually shut down if a disturbance is
                \\ detected on the floor.
                ,
            },
            Portion{
                .fab = "TUT_spellcasting4",
                .view = Rect.new(Coord.new2(TUTORIAL_LEVEL, 0, 11), 10, 10),
                .text =
                \\
                \\
                \\
                \\ Stepping on a $oWielder$.'s corpse will drain it of mana. Many of
                \\ the spellcasting enemies you find will be $oWielder$.s.
                \\
                \\ Wielder corpses are $ogolden$. ($o%$.).
                \\
                \\ $g(Examine a creature with $bv$g to see if it's a $oWielder$g.)
                ,
            },
        },
    },
    Section{
        .title = "Potential",
        .group = "MAGIC",
        .reset_at = 2,
        .rate = 99999999,
        .portions = &[_]Portion{
            Portion{
                .fab = null,
                .text =
                \\
                \\ When you find a mana source, you'll only be able to absorb a percentage
                \\ of it.
                \\
                \\ This is governed by your $oPotential$. stat, which is low when you start off.
                \\
                \\ $cExample$.: if your $oPotential$. is $b40%$., and you find a mana source of
                \\ $b10$., you'll be able to absorb (on average) $b4$. mana from it.
                ,
            },
            Portion{
                .fab = "TUT_potential",
                .text =
                \\
                \\
                \\
                \\ You can increase it with golden items, which have other tradeoffs.
                \\
                \\ $g(For example, a gold crown grants a huge $oPotential$g bonus but reduces
                \\ your Willpower.)$.
                ,
            },
            Portion{
                .fab = null,
                .text =
                \\
                \\ There is no cap on Potential. If it's above 100%, you can absorb extra mana.
                \\
                \\ If you're lucky (or explore branches where golden items are common), you can
                \\ create a spellcaster build in this way.
                \\
                \\ The usual warnings about rHubris apply.
                ,
            },
        },
    },
};

fn drawMap(con: *ui.Console, area: Rect, moblist: []const *Mob) void {
    con.setBorder();

    // Start at one to avoid border
    var dx: usize = 1;
    var dy: usize = 1;

    for (area.start.y..area.end().y) |y| {
        for (area.start.x..area.end().x) |x| {
            const c = Coord.new2(TUTORIAL_LEVEL, x, y);

            var tile = ui.modifyTile(moblist, c, Tile.displayAs(c, false, false));
            tile.fl.wide = true;
            con.setCell(dx, dy, tile);
            con.setCell(dx + 1, dy, .{ .fl = .{ .skip = true } });

            dx += 2;
        }

        dx = 1;
        dy += 1;
    }
}

fn prepareMap(section: *const Section) void {
    mapgen.resetLevel(TUTORIAL_LEVEL);

    var my: usize = 0;
    for (section.portions) |portion| {
        if (portion.fab) |fab_name| {
            const fab = mapgen.Prefab.findPrefabByName(fab_name, &mapgen.n_fabs) orelse {
                std.log.err("Couldn't find prefab {s}", .{fab_name});
                @panic("bailing");
            };
            var room = mapgen.Room{
                .rect = Rect{ .start = Coord.new2(TUTORIAL_LEVEL, 0, my), .width = fab.width, .height = fab.height },
                .prefab = fab,
            };
            mapgen.excavatePrefab(&room, fab, state.alloc, 0, 0);
            state.rooms[TUTORIAL_LEVEL].append(room) catch err.wat();
            my += fab.height + 1;
        } else {
            //my += 12;
        }
    }

    mapgen.generateLayoutMap(TUTORIAL_LEVEL);
}

fn setSection(
    chosen: usize,
    side_con: *ui.Console,
    map_cons: []const *ui.Console,
    text_cons: []const *ui.Console,
    ticks: *usize,
) void {
    ticks.* = 0;

    side_con.clear();
    for (map_cons) |map_con| map_con.clear();
    for (text_cons) |text_con| text_con.clear();

    var last_group: ?[]const u8 = null;
    var y: usize = 0;
    for (SECTIONS, 0..) |sect, sect_i| {
        if (last_group == null or !mem.eql(u8, last_group.?, sect.group)) {
            const bg = colors.percentageOf(colors.CONCRETE, 30);

            // Padding
            if (last_group != null)
                y += 1;

            y += side_con.drawTextAtf(0, y, " .: {s} :. ", .{sect.group}, .{ .bg = bg });
        }

        const ind: u21 = if (sect_i == chosen) '>' else ' ';
        const col: u21 = if (sect_i == chosen) 'c' else '.';
        y += side_con.drawTextAtf(3, y, " $g{u} ${u}{s}", .{ ind, col, sect.title }, .{});
        last_group = sect.group;
    }

    for (SECTIONS[chosen].portions, text_cons[0..SECTIONS[chosen].portions.len]) |portion, text_con| {
        var ty: usize = 1;
        ty += text_con.drawTextAt(0, ty, portion.text, .{});
    }

    prepareMap(&SECTIONS[chosen]);
}

pub fn guideMain() void {
    state.state = .Viewer;
    state.current_level = TUTORIAL_LEVEL;

    const fake_player_coord = Coord.new2(1, 0, 0);
    state.dungeon.at(fake_player_coord).type = .Floor;
    mapgen.placePlayer(fake_player_coord, state.gpa.allocator());
    state.player.kill();

    var tick_timer = std.time.Timer.start() catch unreachable;
    var ticks: usize = 0;

    const d = ui.dimensions(.Whole);
    var console = ui.Console.init(state.alloc, d.width(), d.height());
    defer console.deinit();

    const side_con = ui.Console.initHeap(state.alloc, 26, d.height());
    for (0..d.height()) |y|
        console.setCell(side_con.width, y, .{ .ch = '▌', .fg = colors.CONCRETE });
    console.addSubconsole(side_con, 0, 0);

    var map_cons: [3]*ui.Console = undefined;
    var text_cons: [3]*ui.Console = undefined;

    {
        var y: usize = 0;
        for (&map_cons, &text_cons) |*map_con, *text_con| {
            const MAP_CON_H: usize = 10 + 2;

            const map_con_x = side_con.width + 5;
            map_con.* = ui.Console.initHeap(state.alloc, 20 + 2, MAP_CON_H);
            console.addSubconsole(map_con.*, map_con_x, y);

            text_con.* = ui.Console.initHeap(state.alloc, d.width() - map_con.*.width - map_con_x, MAP_CON_H);
            console.addSubconsole(text_con.*, map_con_x + map_con.*.width + 4, y);

            y += MAP_CON_H;
        }
    }

    var debug = false;
    var debug_con = ui.Console.initHeap(state.alloc, d.width(), d.height());
    debug_con.default_transparent = true;
    console.addSubconsole(debug_con, 0, 0);

    var section: usize = 0;
    var last_section_drawn: usize = 0;

    setSection(section, side_con, &map_cons, &text_cons, &ticks);

    while (state.state != .Quit) {
        if (section != last_section_drawn or tick_timer.read() >= SECTIONS[section].rate * 1_000_000) {
            ticks += 1;
            if (ticks > SECTIONS[section].reset_at) {
                setSection(section, side_con, &map_cons, &text_cons, &ticks);
            }

            last_section_drawn = section;
            tick_timer.reset();

            // Hackish way to prevent reinforcements from showing up
            alert.deinit();
            alert.init();

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const alloc = arena.allocator();

            const moblist = state.createMobList(false, false, state.current_level, alloc);
            //defer moblist.deinit();

            for (SECTIONS[section].portions, map_cons[0..SECTIONS[section].portions.len]) |portion, map_con| {
                if (portion.fab == null) continue;
                drawMap(map_con, portion.view, moblist.items);
            }

            if (debug) {
                drawMap(debug_con, Rect.new(Coord.new(0, 0), WIDTH, HEIGHT), moblist.items);
            } else {
                debug_con.clear();
            }

            console.renderFullyW(.Whole);
            display.present();

            // Tick game after drawing so that initial state is shown.
            main.tickGame(null) catch {};
        }

        var evgen = display.getEvents(ui.FRAMERATE * 2);
        while (evgen.next()) |ev| {
            switch (ev) {
                .Quit => {
                    state.state = .Quit;
                    break;
                },
                .Resize => {},
                .Wheel, .Hover, .Click => {},
                .Key => |k| {
                    switch (k) {
                        .F1 => debug = !debug,
                        .F2 => main.tickGame(null) catch {},
                        .ArrowUp, .ArrowLeft => if (section > 0) {
                            section -= 1;
                            setSection(section, side_con, &map_cons, &text_cons, &ticks);
                        },
                        .ArrowDown, .ArrowRight => if (section < SECTIONS.len - 1) {
                            section += 1;
                            setSection(section, side_con, &map_cons, &text_cons, &ticks);
                        },
                        else => {},
                    }
                },
                .Char => |c| {
                    switch (c) {
                        else => {},
                    }
                },
            }

            break;
        }
    }
}
