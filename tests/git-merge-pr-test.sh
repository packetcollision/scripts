#!/usr/bin/env bash
set -euo pipefail

scripts_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../scripts" >/dev/null 2>&1; pwd -P)"
export PATH="${scripts_dir}:${PATH}"
export NO_COLOR=1

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/git-merge-pr-tests.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

test_count=0

function pass() {
  printf "ok %s\n" "$1"
}

function fail() {
  printf "x %s\n" "$1" >&2
  exit 1
}

function run_test() {
  local name="$1"
  shift

  test_count=$((test_count + 1))
  if (set -euo pipefail; "$@"); then
    pass "$name"
  else
    fail "$name"
  fi
}

function new_remote() {
  local name="$1"
  local remote="${tmp_root}/${name}.git"
  local seed="${tmp_root}/${name}-seed"

  git init --bare "$remote" >/dev/null
  git init "$seed" >/dev/null
  git -C "$seed" config user.name "Git Merge PR Test"
  git -C "$seed" config user.email "git-merge-pr-test@example.com"
  git -C "$seed" config commit.gpgsign false
  printf "%s\n" "$name" > "${seed}/README.md"
  git -C "$seed" add README.md
  git -C "$seed" commit -m "initial" >/dev/null
  git -C "$seed" branch -M main
  git -C "$seed" remote add origin "$remote"
  git -C "$seed" push origin main >/dev/null 2>&1
  git -C "$remote" symbolic-ref HEAD refs/heads/main

  printf "%s\n" "$remote"
}

function clone_remote() {
  local remote="$1"
  local name="$2"
  local work="${tmp_root}/${name}"

  git clone "$remote" "$work" >/dev/null 2>&1
  git -C "$work" config user.name "Git Merge PR Test"
  git -C "$work" config user.email "git-merge-pr-test@example.com"
  git -C "$work" config commit.gpgsign false
  git -C "$work" config mwu.branchPrefix "enelson"
  printf "%s\n" "$work"
}

function output_file() {
  printf "%s\n" "${tmp_root}/output-${test_count}.txt"
}

function assert_contains() {
  local file="$1"
  local expected="$2"

  grep -Fq "$expected" "$file" || {
    printf "Expected output to contain: %s\n" "$expected" >&2
    printf "Actual output:\n" >&2
    sed -n '1,180p' "$file" >&2
    return 1
  }
}

function install_mock_gh() {
  local base_branch="$1"
  local head_branch="$2"
  local head_oid="$3"
  local bin_dir="${tmp_root}/bin"

  mkdir -p "$bin_dir"
  cat > "${bin_dir}/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "pr" && "$2" == "view" ]]; then
  printf "%s\t%s\t%s\n" "$MOCK_PR_BASE_BRANCH" "$MOCK_PR_HEAD_BRANCH" "$MOCK_PR_HEAD_OID"
  exit 0
fi

printf "unexpected gh call: %s\n" "$*" >&2
exit 1
GH
  chmod +x "${bin_dir}/gh"

  export PATH="${bin_dir}:${PATH}"
  export MOCK_PR_BASE_BRANCH="$base_branch"
  export MOCK_PR_HEAD_BRANCH="$head_branch"
  export MOCK_PR_HEAD_OID="$head_oid"
}

function add_pr_branch() {
  local work="$1"
  local branch="$2"
  local remote_branch="$3"

  git -C "$work" switch --quiet -c "$branch" main
  printf "%s\n" "$branch" > "${work}/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -m "add feature" >/dev/null
  git -C "$work" push origin "HEAD:refs/heads/${remote_branch}" >/dev/null 2>&1
  git -C "$work" switch --quiet main
}

function test_merges_no_ff_and_pushes_base() {
  local remote work out head_oid merge_parent_count
  remote="$(new_remote happy)"
  work="$(clone_remote "$remote" happy-work)"
  add_pr_branch "$work" "feature/pr-123" "enelson/feature/pr-123"
  head_oid="$(git -C "$work" rev-parse feature/pr-123)"
  install_mock_gh "main" "enelson/feature/pr-123" "$head_oid"
  out="$(output_file)"

  git -C "$work" merge-pr 123 >"$out" 2>&1

  merge_parent_count="$(git -C "$work" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')"
  [[ "$merge_parent_count" == "3" ]]
  [[ "$(git -C "$work" log -1 --format=%s)" == "Merge PR #123" ]]
  [[ "$(git -C "$work" rev-parse main)" == "$(git -C "$work" rev-parse origin/main)" ]]
  assert_contains "$out" "Merged PR #123"
  assert_contains "$out" "merged: origin/enelson/feature/pr-123 (enelson/feature/pr-123)"
  assert_contains "$out" "pushed: origin/main"
}

function test_merges_without_local_branch() {
  local remote work out head_oid merge_parent_count
  remote="$(new_remote no-local)"
  work="$(clone_remote "$remote" no-local-work)"
  add_pr_branch "$work" "feature/pr-123" "enelson/feature/pr-123"
  head_oid="$(git -C "$work" rev-parse feature/pr-123)"
  git -C "$work" branch -D feature/pr-123 >/dev/null
  install_mock_gh "main" "enelson/feature/pr-123" "$head_oid"
  out="$(output_file)"

  git -C "$work" merge-pr 123 >"$out" 2>&1

  merge_parent_count="$(git -C "$work" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')"
  [[ "$merge_parent_count" == "3" ]]
  [[ "$(git -C "$work" log -1 --format=%s)" == "Merge PR #123" ]]
  [[ "$(git -C "$work" rev-parse main)" == "$(git -C "$work" rev-parse origin/main)" ]]
  assert_contains "$out" "Merged PR #123"
  assert_contains "$out" "merged: origin/enelson/feature/pr-123 (enelson/feature/pr-123)"
}

function test_refuses_wrong_current_branch() {
  local remote work out head_oid
  remote="$(new_remote wrong-current)"
  work="$(clone_remote "$remote" wrong-current-work)"
  add_pr_branch "$work" "feature/pr-123" "enelson/feature/pr-123"
  head_oid="$(git -C "$work" rev-parse feature/pr-123)"
  install_mock_gh "main" "enelson/feature/pr-123" "$head_oid"
  git -C "$work" switch --quiet feature/pr-123
  out="$(output_file)"

  if git -C "$work" merge-pr 123 >"$out" 2>&1; then
    return 1
  fi

  assert_contains "$out" "You are on 'feature/pr-123', but PR #123 targets 'main'."
}

function test_refuses_stale_base() {
  local remote work updater out base_oid head_oid remote_base_oid
  remote="$(new_remote stale-base)"
  work="$(clone_remote "$remote" stale-base-work)"
  add_pr_branch "$work" "feature/pr-123" "enelson/feature/pr-123"
  base_oid="$(git -C "$work" rev-parse main)"
  head_oid="$(git -C "$work" rev-parse feature/pr-123)"
  updater="$(clone_remote "$remote" stale-base-updater)"
  printf "remote update\n" > "${updater}/remote.txt"
  git -C "$updater" add remote.txt
  git -C "$updater" commit -m "update main" >/dev/null
  git -C "$updater" push origin main >/dev/null 2>&1
  remote_base_oid="$(git -C "$updater" rev-parse main)"
  install_mock_gh "main" "enelson/feature/pr-123" "$head_oid"
  out="$(output_file)"

  if git -C "$work" merge-pr 123 >"$out" 2>&1; then
    return 1
  fi

  assert_contains "$out" "Local 'main' is at ${base_oid}, but 'origin/main' is at ${remote_base_oid}."
}

function test_refuses_stale_head_oid() {
  local remote work out
  remote="$(new_remote stale-head)"
  work="$(clone_remote "$remote" stale-head-work)"
  add_pr_branch "$work" "feature/pr-123" "enelson/feature/pr-123"
  # gh reports an older head than what is actually on the remote, simulating a
  # PR head that advanced after gh read it.
  install_mock_gh "main" "enelson/feature/pr-123" "$(git -C "$work" rev-parse main)"
  out="$(output_file)"

  if git -C "$work" merge-pr 123 >"$out" 2>&1; then
    return 1
  fi

  assert_contains "$out" "'origin/enelson/feature/pr-123' is at"
  assert_contains "$out" "but PR #123 head is"
}

function test_refuses_when_head_not_found() {
  local remote work out head_oid
  remote="$(new_remote no-head)"
  work="$(clone_remote "$remote" no-head-work)"
  add_pr_branch "$work" "feature/pr-123" "enelson/feature/pr-123"
  head_oid="$(git -C "$work" rev-parse feature/pr-123)"
  git -C "$work" branch -D feature/pr-123 >/dev/null
  git -C "$work" push origin --delete enelson/feature/pr-123 >/dev/null 2>&1
  install_mock_gh "main" "enelson/feature/pr-123" "$head_oid"
  out="$(output_file)"

  if git -C "$work" merge-pr 123 >"$out" 2>&1; then
    return 1
  fi

  assert_contains "$out" "Could not find PR head 'enelson/feature/pr-123' on 'origin' or as a local branch 'feature/pr-123'."
}

function test_falls_back_to_local_branch() {
  local remote work out head_oid
  remote="$(new_remote local-fallback)"
  work="$(clone_remote "$remote" local-fallback-work)"
  add_pr_branch "$work" "feature/pr-123" "enelson/feature/pr-123"
  head_oid="$(git -C "$work" rev-parse feature/pr-123)"
  # Remove the remote head ref so the script must fall back to the local branch.
  git -C "$work" push origin --delete enelson/feature/pr-123 >/dev/null 2>&1
  git -C "$work" fetch origin --prune >/dev/null 2>&1
  install_mock_gh "main" "enelson/feature/pr-123" "$head_oid"
  out="$(output_file)"

  git -C "$work" merge-pr 123 >"$out" 2>&1

  [[ "$(git -C "$work" log -1 --format=%s)" == "Merge PR #123" ]]
  assert_contains "$out" "merged: feature/pr-123 (enelson/feature/pr-123)"
}

run_test "merges --no-ff and pushes base" test_merges_no_ff_and_pushes_base
run_test "merges without a local branch" test_merges_without_local_branch
run_test "refuses wrong current branch" test_refuses_wrong_current_branch
run_test "refuses stale base" test_refuses_stale_base
run_test "refuses stale head oid" test_refuses_stale_head_oid
run_test "refuses when head not found" test_refuses_when_head_not_found
run_test "falls back to local branch" test_falls_back_to_local_branch

printf "\n%d git-merge-pr tests passed.\n" "$test_count"
