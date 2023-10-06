seed  := "3849171"
iters := "30"

b:
    zig build -Duse-sdl=true

brun:
    zig build -Duse-sdl=true && (RL_NO_SENTRY=1 RL_SEED={{seed}} RL_MODE=normal zig-out/bin/rl 2>| log || less log)

brunv:
    zig build && (RL_NO_SENTRY=1 RL_SEED={{seed}} RL_MODE=viewer zig-out/bin/rl 2>| log || less log)

brunt:
    zig build -Duse-sdl=true && RL_NO_SENTRY=1 RL_SEED={{seed}} RL_MODE=tester zig-out/bin/rl

brunvg:
    zig build -Dtunneler-gif=true && (RL_NO_SENTRY=1 RL_SEED={{seed}} RL_MODE=viewer zig-out/bin/rl 2>| log || less log)

brun-term:
    zig build -Duse-sdl=false && (RL_NO_SENTRY=1 RL_SEED={{seed}} RL_MODE=normal zig-out/bin/rl 2>| log || less log)

an:
    RL_AN_ITERS={{iters}} RL_MODE=analyzer zig-out/bin/rl >| zig-out/output.json
    lua5.3 tools/analyzer-items.lua         < zig-out/output.json >| zig-out/output-items.csv
    lua5.3 tools/analyzer-fabs.lua total    < zig-out/output.json >| zig-out/output-fabs.csv
    lua5.3 tools/analyzer-fabs.lua occurred < zig-out/output.json >| zig-out/output-fabs-occurred.csv
    lua5.3 tools/analyzer-mobs.lua          < zig-out/output.json >| zig-out/output-mobs.csv
