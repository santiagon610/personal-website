#!/bin/sh
# Post (or update in place) a sticky PR comment summarising the Hugo build
# and the `hugo deploy --dryRun` preview. Reads the logs the earlier steps
# tee'd into .ci/ and talks to the Forgejo API with $FORGEJO_TOKEN.
set -eu

marker='<!-- woodpecker:deploy-preview -->'
api="${CI_FORGE_URL}/api/v1/repos/${CI_REPO_OWNER}/${CI_REPO_NAME}"
build_log=.ci/hugo-build.log
deploy_log=.ci/hugo-deploy.log
body=.ci/comment.md
max_rows=50

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

short_sha=$(printf '%.8s' "$CI_COMMIT_SHA")
commit_link="[\`${short_sha}\`](${CI_REPO_URL}/commit/${CI_COMMIT_SHA})"
pipeline_link="[🐦 Pipeline #${CI_PIPELINE_NUMBER}](${CI_PIPELINE_URL})"

{
  echo "$marker"
  if [ "${CI_PIPELINE_STATUS:-success}" != success ]; then
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
