#!/bin/sh

# If you won't want Oathbreaker to phone home to report crashes and other
# bugs, uncomment the following code:
#export RL_NO_SENTRY=1

# Changing the scale to 1 or 1.6 can work if your display is too small
# to accomodate the full window.
#
# The default scale is 2.
#
#export RL_DISPLAY_SCALE = 1

RL_MODE=normal ./rl 2>| log
