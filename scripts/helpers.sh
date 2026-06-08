#!/usr/bin/env bash

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED="\033[31m"
  YELLOW="\033[33m"
  GREEN="\033[32m"
  BLUE="\033[34m"
  PLAIN="\033[0m"
else
  RED=""
  YELLOW=""
  GREEN=""
  BLUE=""
  PLAIN=""
fi

function cur_branch() {
  git branch --show-current
}

function is_git_tree() {
  [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == "true" ]] || fatal "Must be run inside a git work tree"
}

function require_clean_worktree() {
  is_git_tree

  if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    fatal "Your work tree has changes. Commit, stash, or remove them before continuing."
  fi
}

function main_branch() {
  is_git_tree
  local stored_branch

  #attempt to get default branch from git config
  if ! stored_branch="$(git config --get mwu.defaultbranch 2>/dev/null)" || [[ "$stored_branch" == "" ]]; then
    stored_branch=$(get_default_branch)
    [[ -n "$stored_branch" ]] && git config mwu.defaultbranch "${stored_branch}"
  fi
  echo "${stored_branch}"
}

function get_default_branch() {
  is_git_tree
  local remote
  local ref
  local branch

  remote="$(git_scripts_remote)"

  if ref="$(git symbolic-ref --quiet --short "refs/remotes/${remote}/HEAD" 2>/dev/null)"; then
    printf "%s\n" "${ref#${remote}/}"
    return 0
  fi

  for branch in dev develop development main master; do
    if remote_branch_exists "$remote" "$branch" || local_branch_exists "$branch"; then
      printf "%s\n" "$branch"
      return 0
    fi
  done

  fatal "Could not detect the main branch. Set it with: git config mwu.defaultbranch <branch>"
}

function git_config_value_or_default() {
  local key="$1"
  local default="$2"
  local value

  if value="$(git config --get "$key" 2>/dev/null)"; then
    printf "%s\n" "$value"
  else
    printf "%s\n" "$default"
  fi
}

function git_scripts_remote() {
  git_config_value_or_default "mwu.remote" "origin"
}

function git_scripts_branch_prefix() {
  local default_prefix
  default_prefix="$(id -un)"
  git_config_value_or_default "mwu.branchPrefix" "$default_prefix"
}

function local_branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

function remote_branch_exists() {
  local remote="$1"
  local branch="$2"

  git show-ref --verify --quiet "refs/remotes/${remote}/${branch}"
}

function integration_branch_for_remote() {
  local remote="$1"
  local branch

  for branch in dev develop development main master; do
    if remote_branch_exists "$remote" "$branch"; then
      printf "%s\n" "$branch"
      return 0
    fi
  done

  fatal "Could not find a base branch on ${remote}. Expected one of: dev, develop, development, main, master."
}

function fatal() {
  echo -e "${RED}x${PLAIN} ${@}" >&2
  exit 1
}
function error() {
  echo -e "${RED}x${PLAIN} ${@}" >&2
}
function warn() {
  echo -e "${YELLOW}!${PLAIN} ${@}" >&2
}
function info() {
  echo -e "${GREEN}>${PLAIN} ${@}"
}
function success() {
  echo -e "${GREEN}+${PLAIN} ${@}"
}
