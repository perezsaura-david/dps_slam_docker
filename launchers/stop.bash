#!/bin/bash
#
# Tear down the tmuxinator session started by launcher.sh (struct_session.yml).
#
# Safe to run from inside or outside the tmux session.
#
# Every process lives in a pane, so killing the SESSION is what stops the nodes -- no list of
# node names to pkill (such a list silently misses any pane added to struct_session.yml).
#
# Panes get a Ctrl-C first, though, instead of being killed outright: killing a session sends
# SIGHUP, and `ros2 launch` does not forward SIGHUP to its children, so dps_slam / detector /
# fusion nodes would be orphaned and keep running. Ctrl-C (SIGINT) is what `ros2 launch`
# handles and propagates, same as stopping a pane by hand.
#
# Usage: ./stop.bash [grace_seconds]   (default 10)

set +e

SESSIONS=(a2rl)
GRACE=${1:-10}
SHELLS_RE='^(bash|zsh|sh)$'

# Only trust display-message inside tmux: outside it, it reports the most recently used session.
current_session=""
[[ -n "${TMUX}" ]] && current_session=$(tmux display-message -p '#S' 2>/dev/null)

stop_session() {
    local session=$1
    echo "[stop] sending Ctrl-C to every pane of '${session}'"
    # Skip the pane running this script ($TMUX_PANE), or the Ctrl-C would kill us.
    tmux list-panes -s -t "${session}" -F '#{pane_id}' | while read -r pane; do
        [[ "${pane}" == "${TMUX_PANE}" ]] && continue
        tmux send-keys -t "${pane}" C-c
    done

    # Wait until every other pane is back at its shell prompt, or the grace period runs out.
    for ((i = 0; i < GRACE * 2; i++)); do
        busy=$(tmux list-panes -s -t "${session}" -F '#{pane_id} #{pane_current_command}' 2>/dev/null \
            | grep -v "^${TMUX_PANE:-none} " | awk '{print $2}' | grep -Evc "${SHELLS_RE}")
        [[ "${busy}" -eq 0 ]] && break
        sleep 0.5
    done
    [[ "${busy}" -ne 0 ]] && echo "[stop] ${busy} pane(s) still busy after ${GRACE}s, killing anyway"

    echo "[stop] killing session '${session}'"
    tmuxinator stop "${session}" >/dev/null 2>&1
    tmux kill-session -t "${session}" 2>/dev/null
}

for session in "${SESSIONS[@]}"; do
    tmux has-session -t "${session}" 2>/dev/null || continue
    # Leave our own session for last, so this script can finish.
    [[ -n "${current_session}" && "${session}" == "${current_session}" ]] && continue
    stop_session "${session}"
done

# Report (don't kill) ROS nodes that survived: they may belong to something started outside the
# session (e.g. content/eval_run/run.sh), which this script has no business stopping.
leftover=$(pgrep -af -- '--ros-args' | grep -v pgrep)
if [[ -n "${leftover}" ]]; then
    echo "[stop] ROS processes still running (not started by this session, or orphaned):"
    echo "${leftover}" | sed 's/^/    /'
fi

# If we are inside the session, kill it last (this also ends the script).
for session in "${SESSIONS[@]}"; do
    if [[ "${current_session}" == "${session}" ]]; then
        echo "[stop] done (closing this session)."
        stop_session "${current_session}"
    fi
done

echo "[stop] done."
