seed := "3849171"

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
