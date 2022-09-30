seed := "83942"

brun:
    zig build -Duse-sdl=true && (RL_NO_SENTRY=1 RL_SEED={{seed}} RL_MODE=normal zig-out/bin/rl 2>| log || less log)

brun-term:
    zig build -Duse-sdl=false && (RL_NO_SENTRY=1 RL_SEED={{seed}} RL_MODE=normal zig-out/bin/rl 2>| log || less log)
