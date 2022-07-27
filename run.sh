#!/bin/sh

# If you won't want Oathbreaker to phone home to report crashes and other
# bugs, uncomment the following code:
#export RL_NO_SENTRY=1

RL_MODE=normal ./rl 2>| log
