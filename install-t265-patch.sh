#!/usr/bin/env bash
# License: Apache 2.0. See LICENSE file in root directory.
# Copyright(c) 2026 RealSense, Inc. All Rights Reserved.
#
# Turn a fresh stock checkout of upstream realsense-ros 4.59.1 into a
# T265-capable source tree by applying t265-ros-port-v4.59.1.patch.
#
# The base is verified by git tree hash (the pristine 4.59.1 tree), so the
# installer refuses anything that is not byte-identical to 4.59.1.
#
# Default action: apply the patch and stop (no commit, no build).
#
# Usage:
#   git clone https://github.com/realsenseai/realsense-ros.git
#   cd realsense-ros && git checkout 4.59.1
#   install-t265-patch.sh --patch            # patch and stop
#   install-t265-patch.sh --build            # patch + colcon build
#   install-t265-patch.sh --unapply          # back to pristine 4.59.1
#
# Requires a T265-capable librealsense SDK on the system (the 4.59.1 SDK is
# NOT enough: it has no T265 device support).
#
# Exit codes: 0 ok, 1 apply/build failure, 2 base/precondition failure,
#             3 unapply precondition (patch not applied)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DEFAULT="$SCRIPT_DIR/t265-ros-port-v4.59.1.patch"
BASE_TREE="5534b3aa6caba676ced9ec9825e3a3a06e4cf63c"   # pristine 4.59.1 tree
EXPECTED_FILES=11

die() { echo "error: $*" >&2; exit "${2:-1}"; }
say() { echo "$*" >&2; }

usage() {
    sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --repo <dir>       4.59.1 checkout to patch (default: current directory)
  --patch            apply the patch (skipped if already applied) [default]
  --commit           also commit the applied changes (branch: t265-port)
  --build            colcon build of the patched wrapper
  --unapply          reverse-apply the patch (restore pristine 4.59.1)
  --ws <dir>         colcon workspace for --build (default: <repo>/../ws-t265)
  --allow-dirty      proceed despite tracked local modifications
  --yes              do not prompt
  --help             this help
EOF
}

REPO="."
PATCH="$PATCH_DEFAULT"
DO_PATCH=1
DO_COMMIT=0
DO_BUILD=0
DO_UNAPPLY=0
WS=""
ALLOW_DIRTY=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)        REPO="${2:?--repo needs a value}"; shift 2 ;;
        --patch)       DO_PATCH=1; shift ;;
        --commit)      DO_COMMIT=1; shift ;;
        --build)       DO_BUILD=1; shift ;;
        --unapply)     DO_UNAPPLY=1; DO_PATCH=0; shift ;;
        --ws)          WS="${2:?--ws needs a value}"; shift 2 ;;
        --allow-dirty) ALLOW_DIRTY=1; shift ;;
        --yes)         ASSUME_YES=1; shift ;;
        --help|-h)     usage; exit 0 ;;
        *)             die "unknown option: $1 (see --help)" 2 ;;
    esac
done

# --- locate repo ------------------------------------------------------------
[ -d "$REPO" ] || die "repo directory not found: $REPO" 2
REPO="$(cd "$REPO" && pwd)"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 \
    || die "$REPO is not a git repository" 2

# --- patch integrity ----------------------------------------------------------
[ -f "$PATCH" ] || die "patch not found: $PATCH" 2
if grep -q '^GIT binary patch' "$PATCH"; then
    die "patch contains binary sections (unexpected)" 2
fi
patch_files="$(grep -c '^diff --git' "$PATCH")"
[ "$patch_files" -eq "$EXPECTED_FILES" ] \
    || die "patch has ${patch_files} files, expected ${EXPECTED_FILES} (corrupt or wrong version)" 2

# --- base check: pristine 4.59.1 ---------------------------------------------
head_tree="$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
if [ "$head_tree" != "$BASE_TREE" ]; then
    if [ "$DO_UNAPPLY" -eq 1 ]; then
        # not at the base: only meaningful if the patch content is present
        git -C "$REPO" apply --reverse --check "$PATCH" 2>/dev/null \
            || die "base tree mismatch and the patch is not applied in $REPO (nothing to unapply)" 2
    elif grep -q "class PoseProfilesManager" "$REPO/realsense2_camera/include/profile_manager.h"; then
        die "T265 support appears to be already present in $REPO (nothing to do; use --unapply to revert)" 2
    else
        die "base tree mismatch:
  expected pristine 4.59.1 (tree $BASE_TREE)
  got                  $head_tree
Checkout a fresh base with:
  git clone https://github.com/realsenseai/realsense-ros.git
  cd realsense-ros && git checkout 4.59.1" 2
    fi
fi

# --- patch state + dirtiness -------------------------------------------------
patch_applied=0
git -C "$REPO" apply --reverse --check --whitespace=nowarn "$PATCH" 2>/dev/null && patch_applied=1

tracked_changes="$(git -C "$REPO" status --porcelain --untracked-files=no)"
if [ -n "$tracked_changes" ] && [ "$ALLOW_DIRTY" -eq 0 ]; then
    if [ "$patch_applied" -eq 1 ]; then
        say "note: uncommitted tracked changes are the applied patch; continuing"
    else
        die "tracked local modifications present; commit/stash them or pass --allow-dirty:
$tracked_changes" 2
    fi
fi
untracked_count="$(git -C "$REPO" status --porcelain --untracked-files=all | grep -c '^??' || true)"
if [ "$untracked_count" -gt 0 ]; then
    say "note: $untracked_count untracked file(s) in $REPO (ignored)"
fi

# --- unapply -------------------------------------------------------------------
if [ "$DO_UNAPPLY" -eq 1 ]; then
    if ! git -C "$REPO" apply --reverse --check "$PATCH" 2>/dev/null; then
        die "patch is not currently applied in $REPO (nothing to unapply)" 3
    fi
    say "reverse-applying patch in $REPO ..."
    git -C "$REPO" apply --reverse --whitespace=nowarn "$PATCH"
    git -C "$REPO" reset --quiet
    remaining="$(git -C "$REPO" status --porcelain --untracked-files=no)"
    [ -z "$remaining" ] || die "unapply left tracked modifications behind;
restore manually with: git -C $REPO reset --hard
$remaining" 1
    say "done: $REPO is back to pristine 4.59.1"
    exit 0
fi

# --- apply --------------------------------------------------------------------
if [ "$DO_PATCH" -eq 1 ] && [ "$patch_applied" -eq 0 ]; then
    say "applying T265 port patch (${patch_files} files) to: $REPO"
    git -C "$REPO" apply --stat "$PATCH"
    if [ "$ASSUME_YES" -eq 0 ]; then
        printf "Proceed? [y/N] "
        read -r ans
        [ "$ans" = "y" ] || [ "$ans" = "Y" ] || die "aborted by user"
    fi
    git -C "$REPO" apply --whitespace=nowarn "$PATCH" \
        || die "git apply failed" 1
    git -C "$REPO" apply --reverse --check --whitespace=nowarn "$PATCH" \
        || die "patch did not apply completely" 1
    say "applied: $(git -C "$REPO" diff --shortstat | sed 's/^ *//') (+ new files)"
    say "working tree is now 4.59.1 + T265 port (uncommitted)"
elif [ "$DO_PATCH" -eq 1 ]; then
    say "patch already applied; nothing to apply"
fi

# --- commit -------------------------------------------------------------------
if [ "$DO_COMMIT" -eq 1 ]; then
    if [ -z "$(git -C "$REPO" status --porcelain)" ]; then
        say "nothing to commit (patch already committed, or no changes)"
    else
        git -C "$REPO" config user.email >/dev/null \
            || die "git user.email is not set in $REPO; run e.g.
  git config user.name  'Your Name'
  git config user.email 'you@example.com'
and re-run with --commit" 2
        if ! git -C "$REPO" symbolic-ref --quiet HEAD; then
            if git -C "$REPO" show-ref --verify --quiet refs/heads/t265-port; then
                die "detached HEAD, but branch t265-port already exists in $REPO;
remove it first (git -C $REPO branch -D t265-port) and re-run" 2
            fi
            say "detached HEAD: creating branch t265-port for the commit"
            git -C "$REPO" switch -c t265-port
        fi
        git -C "$REPO" add -A
        git -C "$REPO" commit -m "Apply T265 port on top of 4.59.1 (t265-ros-port-v4.59.1.patch)"
        say "committed: $(git -C "$REPO" rev-parse --short HEAD)"
    fi
fi

# --- build --------------------------------------------------------------------
if [ "$DO_BUILD" -eq 1 ]; then
    # source the first available ROS distribution
    ros_setup=""
    for d in /opt/ros/*/setup.sh; do
        if [ -f "$d" ]; then ros_setup="$d"; break; fi
    done
    if [ -z "$ros_setup" ]; then
        die "no ROS installation found in /opt/ros/*/setup.sh; install ROS 2 and re-run" 2
    fi
    # shellcheck disable=SC1090
    source "$ros_setup"

    [ -n "$WS" ] || WS="$REPO/../ws-t265"
    WS="$(cd "$(dirname "$WS")" && pwd)/$(basename "$WS")"
    mkdir -p "$WS/src"
    ws_repo="$WS/src/realsense-ros"

    if [ "$(cd "$ws_repo" 2>/dev/null && pwd)" != "$REPO" ]; then
        say "workspace $ws_repo is not the target repo; re-pointing at $REPO ..."
        rm -rf "$ws_repo"
        mkdir -p "$WS/src"
        ln -s "$REPO" "$ws_repo"
    fi

    say "colcon build (workspace: $WS, ROS: $(basename "$(dirname "$(dirname "$ros_setup")")"))"
    ( cd "$WS" && colcon build \
        --symlink-install \
        --packages-select realsense2_camera_msgs realsense2_description realsense2_camera \
        --cmake-args -DCMAKE_BUILD_TYPE=Release ) \
        || die "colcon build failed" 1

    # smoke test: the node must start and report its version (device optional)
    if command -v ros2 >/dev/null 2>&1; then
        say "smoke test: node startup without device (2 s device wait) ..."
        smoke_out="$( cd "$WS" && source install/setup.bash \
            && timeout 25 ros2 launch realsense2_camera rs_launch.py \
                    wait_for_device_timeout:=2.0 2>&1 )" || true
        if echo "$smoke_out" | grep -q "RealSense ROS v"; then
            say "smoke test: node started and reported its version"
        else
            echo "$smoke_out" >&2
            die "smoke test failed: node did not start" 1
        fi
    else
        say "note: ros2 CLI not found; skipping node smoke test"
    fi
fi

say "OK"
