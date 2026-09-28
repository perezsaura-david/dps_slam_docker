#!/bin/bash
#
# Usage: ./launcher.sh <session.yml> [-s | -r]
#   -s  simulation (default): namespaced drone0/* TF tree, ground-truth metrics
#   -r  real flight: plain map/odom/base_link frames, Livox CustomMsg, no ground truth
# The mode reaches the session file as @settings["mode"] (tmuxinator key=value argument).

usage() {
    echo "Usage: $0 <session.yml> [-s | -r]" >&2
    exit 1
}

# Absolute path to this script. /home/user/bin/foo.sh
SCRIPT=$(readlink -f $0)
# Absolute path this script is in. /home/user/bin
SCRIPTPATH=`dirname $SCRIPT`
cd "$SCRIPTPATH"

[[ -z "$1" || "$1" == -* ]] && usage
SESSION_FILE=$1
shift

MODE=sim
while getopts "sr" opt; do
    case $opt in
        s) MODE=sim ;;
        r) MODE=real ;;
        *) usage ;;
    esac
done

echo "[launcher] $SESSION_FILE in $MODE mode"
tmuxinator start -p "$SESSION_FILE" mode=$MODE
