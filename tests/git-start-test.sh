#!/usr/bin/env bash
set -euo pipefail

scripts_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../scripts" >/dev/null 2>&1; pwd -P)"
export PATH="${scripts_dir}:${PATH}"
export NO_COLOR=1

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/git-start-tests.XXXXXX")"
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
  local first_branch="$2"
  shift 2
  local remote="${tmp_root}/${name}.git"
  local seed="${tmp_root}/${name}-seed"

  git init --bare "$remote" >/dev/null
  git init "$seed" >/dev/null
  git -C "$seed" config user.name "Git Start Test"
  git -C "$seed" config user.email "git-start-test@example.com"
  git -C "$seed" config commit.gpgsign false
  printf "%s\n" "$name" > "${seed}/README.md"
  git -C "$seed" add README.md
  git -C "$seed" commit -m "initial" >/dev/null
  git -C "$seed" branch -M "$first_branch"
  git -C "$seed" remote add origin "$remote"
  git -C "$seed" push origin "$first_branch" >/dev/null 2>&1
  git -C "$remote" symbolic-ref HEAD "refs/heads/${first_branch}"

  local branch
  for branch in "$@"; do
    git -C "$seed" switch -c "$branch" >/dev/null 2>&1
    printf "%s\n" "$branch" > "${seed}/${branch//\//-}.txt"
    git -C "$seed" add .
    git -C "$seed" commit -m "add ${branch}" >/dev/null
    git -C "$seed" push origin "$branch" >/dev/null 2>&1
  done

  printf "%s\n" "$remote"
}

function clone_remote() {
  local remote="$1"
  local name="$2"
  local work="${tmp_root}/${name}"

  git clone "$remote" "$work" >/dev/null 2>&1
  git -C "$work" config user.name "Git Start Test"
  git -C "$work" config user.email "git-start-test@example.com"
  git -C "$work" config commit.gpgsign false
  git -C "$work" config mwu.branchPrefix "enelson"
  printf "%s\n" "$work"
}

function clone_with_named_remote() {
  local remote="$1"
  local name="$2"
  local remote_name="$3"
  local work="${tmp_root}/${name}"

  git clone --origin "$remote_name" "$remote" "$work" >/dev/null 2>&1
  git -C "$work" config user.name "Git Start Test"
  git -C "$work" config user.email "git-start-test@example.com"
  git -C "$work" config commit.gpgsign false
  git -C "$work" config mwu.remote "$remote_name"
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
    sed -n '1,160p' "$file" >&2
    return 1
  }
}

function assert_branch_started() {
  local work="$1"
  local branch="$2"
  local remote_branch="$3"
  local base_branch="$4"

  [[ "$(git -C "$work" branch --show-current)" == "$branch" ]]
  [[ "$(git -C "$work" config --get "branch.${branch}.remote")" == "origin" ]]
  [[ "$(git -C "$work" config --get "branch.${branch}.merge")" == "refs/heads/${remote_branch}" ]]
  [[ "$(git -C "$work" config --get push.default)" == "upstream" ]]
  ! git -C "$work" ls-remote --exit-code --heads origin "$remote_branch" >/dev/null 2>&1
  [[ "$(git -C "$work" rev-parse "$branch")" == "$(git -C "$work" rev-parse "origin/${base_branch}")" ]]
}

function test_base_main() {
  local remote work out
  remote="$(new_remote base-main main)"
  work="$(clone_remote "$remote" base-main-work)"
  out="$(output_file)"

  git -C "$work" start plat-1234-fix-bug >"$out" 2>&1
  assert_branch_started "$work" "plat-1234-fix-bug" "enelson/plat-1234-fix-bug" "main"
  assert_contains "$out" "local:    plat-1234-fix-bug"
  assert_contains "$out" "upstream: origin/enelson/plat-1234-fix-bug (created on first git push)"
  assert_contains "$out" "base:     origin/main"
}

function test_base_dev_preferred_over_main() {
  local remote work out
  remote="$(new_remote base-dev main dev)"
  work="$(clone_remote "$remote" base-dev-work)"
  out="$(output_file)"

  git -C "$work" start plat-1234-fix-bug >"$out" 2>&1
  assert_branch_started "$work" "plat-1234-fix-bug" "enelson/plat-1234-fix-bug" "dev"
  assert_contains "$out" "base:     origin/dev"
}

function test_base_develop() {
  local remote work out
  remote="$(new_remote base-develop develop)"
  work="$(clone_remote "$remote" base-develop-work)"
  out="$(output_file)"

  git -C "$work" start plat-1234-fix-bug >"$out" 2>&1
  assert_branch_started "$work" "plat-1234-fix-bug" "enelson/plat-1234-fix-bug" "develop"
}

function test_base_master() {
  local remote work out
  remote="$(new_remote base-master master)"
  work="$(clone_remote "$remote" base-master-work)"
  out="$(output_file)"

  git -C "$work" start plat-1234-fix-bug >"$out" 2>&1
  assert_branch_started "$work" "plat-1234-fix-bug" "enelson/plat-1234-fix-bug" "master"
}

function test_dirty_worktree_refusal() {
  local remote work out
  remote="$(new_remote dirty main)"
  work="$(clone_remote "$remote" dirty-work)"
  out="$(output_file)"
  printf "dirty\n" > "${work}/dirty.txt"

  if git -C "$work" start plat-1234-fix-bug >"$out" 2>&1; then
    return 1
  fi

  assert_contains "$out" "Your work tree has changes"
}

function test_existing_local_branch_refusal() {
  local remote work out
  remote="$(new_remote existing-local main)"
  work="$(clone_remote "$remote" existing-local-work)"
  out="$(output_file)"
  git -C "$work" branch plat-1234-fix-bug

  if git -C "$work" start plat-1234-fix-bug >"$out" 2>&1; then
    return 1
  fi

  assert_contains "$out" "Local branch already exists"
}

function test_existing_remote_branch_refusal() {
  local remote work out
  remote="$(new_remote existing-remote main)"
  work="$(clone_remote "$remote" existing-remote-work)"
  out="$(output_file)"
  git -C "$work" push origin HEAD:refs/heads/enelson/plat-1234-fix-bug >/dev/null 2>&1

  if git -C "$work" start plat-1234-fix-bug >"$out" 2>&1; then
    return 1
  fi

  assert_contains "$out" "Remote branch already exists"
}

function test_prefixed_branch_refusal() {
  local remote work out
  remote="$(new_remote prefixed main)"
  work="$(clone_remote "$remote" prefixed-work)"
  out="$(output_file)"

  if git -C "$work" start enelson/plat-1234-fix-bug >"$out" 2>&1; then
    return 1
  fi

  assert_contains "$out" "without the 'enelson/' prefix"
}

function test_slash_branch_name() {
  local remote work out
  remote="$(new_remote slash main)"
  work="$(clone_remote "$remote" slash-work)"
  out="$(output_file)"

  git -C "$work" start feature/plat-1234-fix-bug >"$out" 2>&1
  assert_branch_started "$work" "feature/plat-1234-fix-bug" "enelson/feature/plat-1234-fix-bug" "main"
  assert_contains "$out" "upstream: origin/enelson/feature/plat-1234-fix-bug (created on first git push)"
}

function test_custom_remote() {
  local remote work out
  remote="$(new_remote custom-remote main)"
  work="$(clone_with_named_remote "$remote" custom-remote-work forgejo)"
  out="$(output_file)"

  git -C "$work" start plat-1234-fix-bug >"$out" 2>&1
  [[ "$(git -C "$work" config --get branch.plat-1234-fix-bug.remote)" == "forgejo" ]]
  [[ "$(git -C "$work" config --get branch.plat-1234-fix-bug.merge)" == "refs/heads/enelson/plat-1234-fix-bug" ]]
  [[ "$(git -C "$work" rev-parse plat-1234-fix-bug)" == "$(git -C "$work" rev-parse forgejo/main)" ]]
  ! git -C "$work" ls-remote --exit-code --heads forgejo enelson/plat-1234-fix-bug >/dev/null 2>&1
  assert_contains "$out" "upstream: forgejo/enelson/plat-1234-fix-bug (created on first git push)"
}

function test_custom_prefix() {
  local remote work out
  remote="$(new_remote custom-prefix main)"
  work="$(clone_remote "$remote" custom-prefix-work)"
  out="$(output_file)"
  git -C "$work" config mwu.branchPrefix "dnelson"

  git -C "$work" start plat-1234-fix-bug >"$out" 2>&1
  assert_branch_started "$work" "plat-1234-fix-bug" "dnelson/plat-1234-fix-bug" "main"
  assert_contains "$out" "upstream: origin/dnelson/plat-1234-fix-bug (created on first git push)"
}

function test_plain_push_creates_configured_remote_branch() {
  local remote work out
  remote="$(new_remote push-later main)"
  work="$(clone_remote "$remote" push-later-work)"
  out="$(output_file)"

  git -C "$work" start plat-1234-fix-bug >"$out" 2>&1
  ! git -C "$work" ls-remote --exit-code --heads origin enelson/plat-1234-fix-bug >/dev/null 2>&1
  git -C "$work" push >/dev/null 2>&1
  git -C "$work" ls-remote --exit-code --heads origin enelson/plat-1234-fix-bug >/dev/null
}

run_test "uses main fallback" test_base_main
run_test "prefers dev before main" test_base_dev_preferred_over_main
run_test "uses develop fallback" test_base_develop
run_test "uses master fallback" test_base_master
run_test "refuses dirty work trees" test_dirty_worktree_refusal
run_test "refuses existing local branches" test_existing_local_branch_refusal
run_test "refuses existing remote branches" test_existing_remote_branch_refusal
run_test "refuses already-prefixed branch names" test_prefixed_branch_refusal
run_test "supports slash-containing branch names" test_slash_branch_name
run_test "supports custom remotes" test_custom_remote
run_test "supports custom prefixes" test_custom_prefix
run_test "plain git push creates the configured remote branch" test_plain_push_creates_configured_remote_branch

printf "\n%d git-start tests passed.\n" "$test_count"
