#!/bin/sh
# Run one linter over the repo (skipping the vendored theme and build output),
# keep its output and exit code in .ci/lint/ for the PR comment, and exit with
# the linter's status so the step fails as usual.
#
# Usage: lint.sh markdown|shell|yaml|json|prettier
set -u

# Files outside the vendored theme and build output, e.g. `files -name '*.sh'`.
files() {
  find . \( -path ./.git -o -path ./themes -o -path ./public -o -path ./resources \
    -o -name node_modules \) -prune -o -type f \( "$@" \) -print | sort
}

check_json() {
  rc=0
  for f in $(files -name '*.json'); do
    jq empty "$f" || { echo "$f: invalid JSON"; rc=1; }
  done
  return "$rc"
}

id=$1
case "$id" in
  markdown) label="Markdown (markdownlint)" ;;
  shell) label="Shell (ShellCheck)" ;;
  yaml) label="YAML (yamllint)" ;;
  json) label="JSON (jq)" ;;
  prettier) label="Formatting (Prettier)" ;;
  *) echo "unknown linter: $id" >&2; exit 2 ;;
esac

dir=.ci/lint
mkdir -p "$dir"
printf '%s\n' "$label" > "$dir/$id.label"

# shellcheck disable=SC2046 # word-splitting the shell file list is intended
case "$id" in
  markdown) markdownlint-cli2 ;;
  shell) shellcheck $(files -name '*.sh') ;;
  yaml) yamllint --format parsable . ;;
  json) check_json ;;
  prettier) prettier --check . ;;
esac > "$dir/$id.log" 2>&1
rc=$?

cat "$dir/$id.log"
echo "$rc" > "$dir/$id.rc"
exit "$rc"
