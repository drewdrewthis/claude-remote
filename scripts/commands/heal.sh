#
# claude-remote heal — fix git worktree paths after sync
# Sourced by claude-remote.sh dispatcher (SCRIPT_DIR and config already loaded)
#
# Git worktrees store absolute paths in two places:
#   1. <worktree>/.git         — "gitdir: /abs/path/to/.git/worktrees/<name>"
#   2. .git/worktrees/<name>/gitdir — "/abs/path/to/<worktree>/.git"
#
# In submodule repos, the paths go through .git/modules/<mod>/worktrees/<name>.
#
# When synced between machines with different base dirs, ALL of these break.
# Additionally, worktree metadata dirs may not sync at all, requiring repair.
#

# _resolve_branch <worktree-name> <git-dir>
# Try to find the branch name from a worktree directory name.
# Convention: worktree-<prefix>-<rest> -> <prefix>/<rest>
_resolve_branch() {
    local wt_name="$1"
    local git_dir="$2"
    local stripped="${wt_name#worktree-}"

    # Try: replace first dash with /
    local guess1
    guess1=$(echo "$stripped" | sed 's/-/\//')

    # Try: exact name as branch
    local guess2="$stripped"

    for guess in "$guess1" "$guess2"; do
        if git --git-dir="$git_dir" show-ref --verify --quiet "refs/heads/$guess" 2>/dev/null; then
            echo "$guess"
            return 0
        fi
        if git --git-dir="$git_dir" show-ref --verify --quiet "refs/remotes/origin/$guess" 2>/dev/null; then
            echo "$guess"
            return 0
        fi
    done

    return 1
}

_heal_paths() {
    local base_dir="$1"
    local wrong="$2"
    local right="$3"
    local is_macos="$4"  # "true" or "false" — affects sed -i syntax
    local fixed=0

    local sed_inplace
    if [[ "$is_macos" == "true" ]]; then
        sed_inplace=(sed -i '')
    else
        sed_inplace=(sed -i)
    fi

    echo "Healing worktree paths in $base_dir..."
    echo "  replacing: $wrong -> $right"

    # --- Part 1: Fix .git pointer files in worktree checkouts ---
    while IFS= read -r -d '' f; do
        # Only process files with absolute gitdir paths (skip submodule relative paths)
        if ! grep -q "^gitdir: /" "$f" 2>/dev/null; then
            continue
        fi
        if grep -q "$wrong" "$f" 2>/dev/null; then
            "${sed_inplace[@]}" "s|$wrong|$right|g" "$f"
            echo "  fixed .git: $(basename "$(dirname "$f")")"
            ((fixed++))
        fi
    done < <(find "$base_dir" -maxdepth 4 -name .git -not -type d -print0 2>/dev/null)

    # --- Part 2: Fix reverse gitdir pointers inside .git dirs ---
    # Search only inside .git directories (maxdepth-limited) to avoid crawling node_modules
    while IFS= read -r -d '' gitdir; do
        while IFS= read -r -d '' f; do
            if grep -q "$wrong" "$f" 2>/dev/null; then
                "${sed_inplace[@]}" "s|$wrong|$right|g" "$f"
                echo "  fixed gitdir: $(basename "$(dirname "$f")")"
                ((fixed++))
            fi
        done < <(find "$gitdir" -path '*/worktrees/*/gitdir' -print0 2>/dev/null)
    done < <(find "$base_dir" -maxdepth 3 -name .git -type d -print0 2>/dev/null)

    echo "  fixed $fixed path(s)"
    return 0
}

_repair_worktrees() {
    local base_dir="$1"
    local repaired=0
    local skipped=0

    echo ""
    echo "Repairing orphaned worktrees in $base_dir..."

    local wt_dir wt_name gitdir_target git_dir branch

    # Find all .git files (worktree pointers) that point to non-existent metadata dirs
    while IFS= read -r -d '' dotgit; do
        wt_dir=$(dirname "$dotgit")
        wt_name=$(basename "$wt_dir")

        # Read the gitdir pointer — skip non-absolute paths (submodule .git files)
        gitdir_target=$(sed 's/^gitdir: //' "$dotgit" 2>/dev/null)
        if [[ "$gitdir_target" != /* ]]; then
            continue
        fi

        # Only process paths that go through /worktrees/ (actual worktree pointers)
        if [[ "$gitdir_target" != *"/worktrees/"* ]]; then
            continue
        fi

        # Skip if the metadata dir already exists and is valid
        if [[ -d "$gitdir_target" ]] && [[ -f "$gitdir_target/HEAD" ]]; then
            continue
        fi

        # The metadata dir is missing — need to recreate it
        # Parse the git dir from the gitdir path (strip /worktrees/<name>)
        git_dir="${gitdir_target%/worktrees/*}"

        if [[ ! -d "$git_dir" ]]; then
            echo "  SKIP $wt_name: parent git dir not found: $git_dir"
            ((skipped++))
            continue
        fi

        # Resolve branch name
        branch=""
        if ! branch=$(_resolve_branch "$wt_name" "$git_dir") || [[ -z "$branch" ]]; then
            echo "  SKIP $wt_name: could not resolve branch"
            ((skipped++))
            continue
        fi

        echo "  repairing: $wt_name -> $branch"

        # Create the worktree metadata directory
        mkdir -p "$gitdir_target"

        # commondir: relative path from metadata dir to the parent git dir
        # always ../.. since layout is <git-dir>/worktrees/<name>
        echo "../.." > "$gitdir_target/commondir"

        # gitdir: absolute path back to the worktree's .git file
        echo "$wt_dir/.git" > "$gitdir_target/gitdir"

        # HEAD: ref to the branch
        echo "ref: refs/heads/$branch" > "$gitdir_target/HEAD"

        # Verify it works
        if git -C "$wt_dir" rev-parse --git-dir &>/dev/null; then
            echo "    OK"
            ((repaired++))
        else
            echo "    FAILED — cleaning up"
            rm -rf "$gitdir_target"
            ((skipped++))
        fi
    done < <(find "$base_dir" -maxdepth 4 -name .git -not -type d -print0 2>/dev/null)

    echo "  repaired $repaired, skipped $skipped"
}

_run_git_worktree_repair() {
    local base_dir="$1"
    local git_dir

    echo ""
    echo "Running git worktree repair..."

    # Plain repos: .git/worktrees/
    while IFS= read -r -d '' wt_dir; do
        git_dir=$(dirname "$(dirname "$wt_dir")")
        if git --git-dir="$git_dir" rev-parse --git-dir &>/dev/null; then
            echo "  $git_dir"
            git --git-dir="$git_dir" worktree repair 2>&1 | sed 's/^/    /'
        fi
    done < <(find "$base_dir" -maxdepth 3 -path '*/.git/worktrees' -type d -print0 2>/dev/null)

    # Submodule repos: .git/modules/<mod>/worktrees/
    while IFS= read -r -d '' wt_dir; do
        git_dir=$(dirname "$wt_dir")
        if git --git-dir="$git_dir" rev-parse --git-dir &>/dev/null; then
            echo "  $git_dir (submodule)"
            git --git-dir="$git_dir" worktree repair 2>&1 | sed 's/^/    /'
        fi
    done < <(find "$base_dir" -maxdepth 6 -path '*/.git/modules/*/worktrees' -type d -print0 2>/dev/null)

    echo "Done."
}

_heal_local() {
    _heal_paths "$LOCAL_MOUNT" "$REMOTE_DIR" "$LOCAL_MOUNT" "true"
    _repair_worktrees "$LOCAL_MOUNT"
    _run_git_worktree_repair "$LOCAL_MOUNT"
}

_heal_remote() {
    local wrong="$LOCAL_MOUNT"
    local right="$REMOTE_DIR"

    echo "Healing remote worktree paths..."

    ssh -o ConnectTimeout=5 "$REMOTE_HOST" bash -s -- "$right" "$wrong" <<'SCRIPT'
right="$1"
wrong="$2"
fixed=0

# Part 1: Fix .git pointer files (only absolute gitdir paths)
while IFS= read -r -d '' f; do
    if ! grep -q "^gitdir: /" "$f" 2>/dev/null; then
        continue
    fi
    if grep -q "$wrong" "$f" 2>/dev/null; then
        sed -i "s|$wrong|$right|g" "$f"
        echo "  fixed .git: $(basename "$(dirname "$f")")"
        ((fixed++))
    fi
done < <(find "$right" -maxdepth 4 -name .git -not -type d -print0 2>/dev/null)

# Part 2: Fix reverse gitdir pointers (search only inside .git dirs)
while IFS= read -r -d '' gitdir; do
    while IFS= read -r -d '' f; do
        if grep -q "$wrong" "$f" 2>/dev/null; then
            sed -i "s|$wrong|$right|g" "$f"
            echo "  fixed gitdir: $(basename "$(dirname "$f")")"
            ((fixed++))
        fi
    done < <(find "$gitdir" -path '*/worktrees/*/gitdir' -print0 2>/dev/null)
done < <(find "$right" -maxdepth 3 -name .git -type d -print0 2>/dev/null)

echo "  fixed $fixed path(s)"

# Part 3: Repair orphaned worktrees
echo ""
echo "Repairing orphaned worktrees..."
repaired=0
skipped=0

while IFS= read -r -d '' dotgit; do
    wt_dir=$(dirname "$dotgit")
    wt_name=$(basename "$wt_dir")
    gitdir_target=$(sed 's/^gitdir: //' "$dotgit" 2>/dev/null)

    # Skip non-absolute and non-worktree paths
    [[ "$gitdir_target" != /* ]] && continue
    [[ "$gitdir_target" != *"/worktrees/"* ]] && continue

    # Skip if metadata exists
    if [[ -d "$gitdir_target" ]] && [[ -f "$gitdir_target/HEAD" ]]; then
        continue
    fi

    git_dir="${gitdir_target%/worktrees/*}"
    if [[ ! -d "$git_dir" ]]; then
        echo "  SKIP $wt_name: parent git dir missing"
        ((skipped++))
        continue
    fi

    # Resolve branch: try first-dash-to-slash, then exact
    stripped="${wt_name#worktree-}"
    guess1=$(echo "$stripped" | sed 's/-/\//')
    branch=""
    for guess in "$guess1" "$stripped"; do
        if git --git-dir="$git_dir" show-ref --verify --quiet "refs/heads/$guess" 2>/dev/null ||
           git --git-dir="$git_dir" show-ref --verify --quiet "refs/remotes/origin/$guess" 2>/dev/null; then
            branch="$guess"
            break
        fi
    done

    if [[ -z "$branch" ]]; then
        echo "  SKIP $wt_name: cannot resolve branch"
        ((skipped++))
        continue
    fi

    echo "  repairing: $wt_name -> $branch"
    mkdir -p "$gitdir_target"
    echo "../.." > "$gitdir_target/commondir"
    echo "$wt_dir/.git" > "$gitdir_target/gitdir"
    echo "ref: refs/heads/$branch" > "$gitdir_target/HEAD"

    if git -C "$wt_dir" rev-parse --git-dir &>/dev/null; then
        echo "    OK"
        ((repaired++))
    else
        echo "    FAILED"
        rm -rf "$gitdir_target"
        ((skipped++))
    fi
done < <(find "$right" -maxdepth 4 -name .git -not -type d -print0 2>/dev/null)

echo "  repaired $repaired, skipped $skipped"

# Part 4: git worktree repair
echo ""
echo "Running git worktree repair..."
while IFS= read -r -d '' wt_dir; do
    git_dir=$(dirname "$(dirname "$wt_dir")")
    if git --git-dir="$git_dir" rev-parse --git-dir &>/dev/null; then
        echo "  $git_dir"
        git --git-dir="$git_dir" worktree repair 2>&1 | sed 's/^/    /'
    fi
done < <(find "$right" -maxdepth 3 -path '*/.git/worktrees' -type d -print0 2>/dev/null)

while IFS= read -r -d '' wt_dir; do
    git_dir=$(dirname "$wt_dir")
    if git --git-dir="$git_dir" rev-parse --git-dir &>/dev/null; then
        echo "  $git_dir (submodule)"
        git --git-dir="$git_dir" worktree repair 2>&1 | sed 's/^/    /'
    fi
done < <(find "$right" -maxdepth 6 -path '*/.git/modules/*/worktrees' -type d -print0 2>/dev/null)

echo "Done."
SCRIPT
}

cmd_heal() {
    case "${1:-both}" in
        local)  _heal_local ;;
        remote) _heal_remote ;;
        both)   _heal_local; _heal_remote ;;
        *)      echo "Usage: claude-remote heal [local|remote|both]" >&2; return 1 ;;
    esac
}
