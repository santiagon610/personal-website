#!/bin/sh
# Post (or update in place) a sticky PR comment summarising the lint results,
# the Hugo build and the `hugo deploy --dryRun` preview. Reads the logs the
# earlier steps left in .ci/ and talks to the Forgejo API with $FORGEJO_TOKEN.
set -eu

marker='<!-- woodpecker:deploy-preview -->'
api="${CI_FORGE_URL}/api/v1/repos/${CI_REPO_OWNER}/${CI_REPO_NAME}"
build_log=.ci/hugo-build.log
deploy_log=.ci/hugo-deploy.log
body=.ci/comment.md
max_rows=50
lint_dir=.ci/lint
lint_ids="markdown shell yaml json prettier"
max_log_lines=60

touch "$build_log" "$deploy_log"

# Build stats come from Hugo's box-drawn table, e.g. " Pages            │ 84 ".
stat() {
  awk -F'│' -v key="$1" '{ k = $1; gsub(/^ +| +$/, "", k) } k == key { gsub(/ /, "", $2); print $2; exit }' "$build_log"
}
build_time=$(sed -n 's/^Total in //p' "$build_log" | tail -n 1)

# "[DRY RUN] Would upload: path (5.2 kB, Content-Type: "text/html"): md5 differs"
uploads=$(sed -n 's/^.*\[DRY RUN\] Would upload: \([^ ]*\) (\([^,)]*\)[^)]*): \(.*\)$/\1\t\2\t\3/p' "$deploy_log")
# "[DRY RUN] Would delete path"
deletes=$(sed -n 's/^.*\[DRY RUN\] Would delete \(.*\)$/\1/p' "$deploy_log")
n_up=$(printf '%s' "$uploads" | grep -c . || true)
n_del=$(printf '%s' "$deletes" | grep -c . || true)
upload_total=$(sed -n 's/^.*totaling \(.*\), and .*$/\1/p' "$deploy_log")
# 'Deploying to target "production" (s3://bucket)'
target_url=$(sed -n 's/^Deploying to target .* (\(.*\))$/\1/p' "$deploy_log")

# Issue count per linter, from each tool's own output format.
lint_count() {
  log="$lint_dir/$1.log"
  case "$1" in
    markdown) sed -n 's/^Summary: \([0-9]*\) issue.*/\1/p' "$log" ;;
    shell) grep -c '\^-- SC' "$log" ;;
    yaml) grep -c '^[^:]*:[0-9]*:[0-9]*: \[' "$log" ;;
    json) grep -c ': invalid JSON$' "$log" ;;
    prettier) grep -v 'Code style issues' "$log" | grep -c '^\[warn\]' ;;
  esac
}

lint_failed=""
for id in $lint_ids; do
  if [ -f "$lint_dir/$id.rc" ] && [ "$(cat "$lint_dir/$id.rc")" != 0 ]; then
    lint_failed="$lint_failed $id"
  fi
done

short_sha=$(printf '%.8s' "$CI_COMMIT_SHA")
commit_link="[\`${short_sha}\`](${CI_REPO_URL}/commit/${CI_COMMIT_SHA})"
pipeline_link="[🐦 Pipeline #${CI_PIPELINE_NUMBER}](${CI_PIPELINE_URL})"

{
  echo "$marker"
  if [ -n "$lint_failed" ]; then
    echo "## 🧹 Lint failed — build skipped"
    echo
    echo "🙅 Fix the lint findings below and push again; the build and deploy preview run once lint is green."
  elif [ "${CI_PIPELINE_STATUS:-success}" != success ]; then
    echo "## ❌ Deploy preview failed"
    echo
    echo "💥 Something broke before the preview finished — check the ${pipeline_link} logs. 🔍"
  elif [ "$n_up" -eq 0 ] && [ "$n_del" -eq 0 ]; then
    echo "## ✅ Deploy preview: nothing to ship"
    echo
    echo "😎 Production already matches this build — merging won't upload or delete anything."
  else
    echo "## 🚀 Deploy preview: changes incoming"
    echo
    echo "📦 Merging will sync **${n_up}** upload(s) (${upload_total:-?}) and **${n_del}** deletion(s) to 🪣 \`${target_url:-the deploy target}\`, then invalidate 🌩️ CloudFront."
  fi
  echo

  echo "### 🧹 Lint"
  echo
  echo "| | Check | Result |"
  echo "|---|---|---|"
  for id in $lint_ids; do
    label=$(cat "$lint_dir/$id.label" 2>/dev/null || echo "$id")
    if [ ! -f "$lint_dir/$id.rc" ]; then
      echo "| ⏭️ | ${label} | didn't run |"
    elif [ "$(cat "$lint_dir/$id.rc")" = 0 ]; then
      echo "| ✅ | ${label} | clean |"
    else
      echo "| ❌ | ${label} | $(lint_count "$id" || true) issue(s) |"
    fi
  done
  echo
  for id in $lint_failed; do
    log="$lint_dir/$id.log"
    echo "<details open>"
    echo "<summary>❌ $(cat "$lint_dir/$id.label") output</summary>"
    echo
    echo '~~~text'
    # Strip ANSI colour codes; cap long logs.
    sed 's/\x1b\[[0-9;]*m//g' "$log" | head -n "$max_log_lines"
    if [ "$(wc -l < "$log")" -gt "$max_log_lines" ]; then
      echo "… truncated, see the pipeline logs"
    fi
    echo '~~~'
    echo
    echo "</details>"
    echo
  done

  if [ ! -s "$build_log" ]; then
    echo "### ⏭️ Build"
    echo
    echo "Skipped — it only runs once every lint check passes."
    echo
  else
    echo "### 🏗️ Build"
    echo
    echo "| | Metric | Value |"
    echo "|---|---|---:|"
    echo "| 📄 | Pages | $(stat Pages) |"
    echo "| 🖼️ | Processed images | $(stat 'Processed images') |"
    echo "| 📁 | Static files | $(stat 'Static files') |"
    echo "| 🔀 | Aliases | $(stat Aliases) |"
    echo "| ⏱️ | Build time | ${build_time:-n/a} |"
    echo
  fi

  if [ "$n_up" -gt 0 ] || [ "$n_del" -gt 0 ]; then
    echo "### 🔎 File changes"
    echo
    echo "<details$([ $((n_up + n_del)) -le 15 ] && echo ' open')>"
    echo "<summary>⬆️ ${n_up} upload(s) · 🗑️ ${n_del} deletion(s)</summary>"
    echo
    echo "| | File | Size | Why |"
    echo "|---|---|---:|---|"
    {
      printf '%s\n' "$uploads" | awk -F'\t' 'NF {
        icon = "✏️"; why = $3
        if ($3 == "not found at target") { icon = "🆕"; why = "new file" }
        else if ($3 == "remote md5 missing") { icon = "❓" }
        else if ($3 == "--force") { icon = "💪" }
        printf "| %s | `%s` | %s | %s |\n", icon, $1, $2, why
      }'
      printf '%s\n' "$deletes" | awk 'NF { printf "| 🗑️ | `%s` | | removed |\n", $0 }'
    } | head -n "$max_rows"
    if [ $((n_up + n_del)) -gt "$max_rows" ]; then
      echo
      echo "➕ …and $((n_up + n_del - max_rows)) more — see the ${pipeline_link} logs."
    fi
    echo
    echo "</details>"
    echo
  fi

  echo "---"
  echo "${pipeline_link} · 🔖 ${commit_link} · 🕒 $(date -u '+%Y-%m-%d %H:%M UTC')"
} > "$body"

auth="Authorization: token ${FORGEJO_TOKEN}"
payload=$(jq -n --rawfile body "$body" '{body: $body}')
existing=$(curl -fsS -H "$auth" "${api}/issues/${CI_COMMIT_PULL_REQUEST}/comments" |
  jq -r --arg m "$marker" '[.[] | select(.body | startswith($m))] | last | .id // empty')

if [ -n "$existing" ]; then
  curl -fsS -o /dev/null -X PATCH -H "$auth" -H 'Content-Type: application/json' \
    -d "$payload" "${api}/issues/comments/${existing}"
  echo "💬 Updated comment ${existing} on PR #${CI_COMMIT_PULL_REQUEST}"
else
  curl -fsS -o /dev/null -X POST -H "$auth" -H 'Content-Type: application/json' \
    -d "$payload" "${api}/issues/${CI_COMMIT_PULL_REQUEST}/comments"
  echo "💬 Posted comment on PR #${CI_COMMIT_PULL_REQUEST}"
fi
