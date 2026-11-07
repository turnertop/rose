#!/bin/sh
# Keep the active guard outside the working tree so branch switches retain it.
set -eu
ROSE_GUARD_ROOT="$(git rev-parse --show-toplevel)"
ROSE_GUARD_SOURCE="$ROSE_GUARD_ROOT/.githooks/pre-push"
ROSE_GUARD_DIRECTORY="$(git rev-parse --path-format=absolute --git-path rose-publication-hooks)"
ROSE_EXISTING_HOOKS="$(git config --local --get core.hooksPath || :)"
case "$ROSE_EXISTING_HOOKS" in
    ''|.githooks|"$ROSE_GUARD_DIRECTORY") ;;
    *) printf 'Existing custom hooks configuration requires review; nothing changed.\n' >&2; exit 1 ;;
esac
test -f "$ROSE_GUARD_SOURCE"
mkdir -p "$ROSE_GUARD_DIRECTORY"
cp "$ROSE_GUARD_SOURCE" "$ROSE_GUARD_DIRECTORY/pre-push"
chmod 755 "$ROSE_GUARD_DIRECTORY/pre-push"
git config --local core.hooksPath "$ROSE_GUARD_DIRECTORY"
printf 'Installed the branch-independent local push guard. Publication remains blocked.\n'
