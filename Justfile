brun:
    zig build -Duse-sdl=true && (RL_NO_SENTRY=1 RL_SEED=83942 RL_MODE=normal zig-out/bin/rl 2>| log || less log)

brun-term:
    zig build -Duse-sdl=false && (RL_NO_SENTRY=1 RL_SEED=83942 RL_MODE=normal zig-out/bin/rl 2>| log || less log)
