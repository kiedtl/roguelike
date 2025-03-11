#!/bin/sh

# If you won't want Oathbreaker to phone home to report crashes and other
# bugs, uncomment the following code:
#export RL_NO_SENTRY=1

# The default scale is 1.
#
# Changing the scale to, say, 1.4 if your eyes are damaged. A scale of 2 might
# not fit on your screen.
#
#export RL_DISPLAY_SCALE = 1.4

RL_MODE=normal ./rl 2>| log
