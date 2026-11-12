#!/usr/bin/env bash
# Watches upstream for the fork (.github/workflows/upstream-watch.yml):
# keeps one open issue listing upstream's commits not merged yet, their
# Chinese release notes, and the fork's customised files they touch; and
# opens an issue when baocode-dev makes another repository public (the
# phone app's, say).
#
#   tool/upstream_watch.sh            update the issues (needs GH_TOKEN)
#   DRY_RUN=1 tool/upstream_watch.sh  print what it would write
#
# Needs a remote named upstream fetched (git fetch upstream main).
set -euo pipefail

UPSTREAM=baocode-dev/baocode
ORG=baocode-dev
KNOWN_REPOS=(baocode relay)
REPO=${GITHUB_REPOSITORY:-y0un922/baogong}
FORK_REF=${FORK_REF:-main}
UPSTREAM_REF=${UPSTREAM_REF:-upstream/main}
WATCH_LABEL=upstream-watch
ORG_LABEL=org-watch
dry() { [ "${DRY_RUN:-}" = 1 ]; }

# --- Upstream's commits not merged yet ---

head=$(git rev-parse "$UPSTREAM_REF")
base=$(git merge-base "$FORK_REF" "$UPSTREAM_REF")
count=$(git rev-list --count --no-merges "$FORK_REF..$UPSTREAM_REF")

commit_list() {
  git log --no-merges --format="- [\`%h\`](https://github.com/$UPSTREAM/commit/%H) %s（%ad）" \
    --date=short "$@" | head -150
}

body() {
  echo "<!-- upstream-head: $head -->"
  echo "上游 [\`$UPSTREAM\`](https://github.com/$UPSTREAM) 有 **$count** 个提交还没合进本 fork（上次合并到 [\`${base:0:8}\`](https://github.com/$UPSTREAM/commit/$base)）。"
  echo
  notes=$(git diff --name-only --diff-filter=AM "$base" "$UPSTREAM_REF" -- 'release-notes/*.zh.md' | sort -V)
  if [ -n "$notes" ]; then
    echo "## 更新说明"
    for file in $notes; do
      echo
      echo "### $(basename "$file" .zh.md)"
      echo
      git show "$UPSTREAM_REF:$file"
    done
    echo
  fi
  echo "## 与 fork 定制重叠的文件"
  echo
  overlap=$(comm -12 \
    <(git diff --name-only "$base" "$FORK_REF" | sort) \
    <(git diff --name-only "$base" "$UPSTREAM_REF" | sort))
  if [ -n "$overlap" ]; then
    echo "合并时可能要处理冲突："
    echo
    sed 's/.*/- `&`/' <<<"$overlap"
  else
    echo "没有，合并应该不会冲突。"
  fi
  echo
  echo "## 提交"
  echo
  commit_list "$FORK_REF..$UPSTREAM_REF"
  [ "$count" -gt 150 ] && echo "- ……还有 $((count - 150)) 个"
  echo
  echo "合并方法见 \`docs/fork.md\` 的「审查上游后合并」。合并后这个 issue 会自动关闭。"
}

title="上游有 $count 个新提交"
latest=$(git diff --name-only --diff-filter=A "$base" "$UPSTREAM_REF" -- 'release-notes/*.zh.md' |
  sed 's|release-notes/||; s|\.zh\.md||' | sort -V | tail -1)
[ -n "$latest" ] && title="${title}（含 ${latest}）"

if dry; then
  echo "=== issue: $title"
  body
else
  gh label create "$WATCH_LABEL" -R "$REPO" --color 0e8a16 --description "上游更新" --force >/dev/null
  open=$(gh issue list -R "$REPO" --label "$WATCH_LABEL" --state open --json number --jq '.[0].number // empty')
  if [ "$count" -eq 0 ]; then
    [ -n "$open" ] && gh issue close "$open" -R "$REPO" --comment "上游的提交都已合并。"
  elif [ -z "$open" ]; then
    gh issue create -R "$REPO" --label "$WATCH_LABEL" --title "$title" --body "$(body)"
  else
    old=$(gh issue view "$open" -R "$REPO" --json body --jq .body |
      sed -n 's/.*upstream-head: \([0-9a-f]*\).*/\1/p')
    if [ "$old" != "$head" ]; then
      gh issue edit "$open" -R "$REPO" --title "$title" --body "$(body)"
      # A comment, so the change is notified, not only edited in.
      new=$(git cat-file -e "$old" 2>/dev/null && commit_list "$old..$head" || true)
      gh issue comment "$open" -R "$REPO" --body "上游又有新提交，正文已更新。
${new}"
    fi
  fi
fi

# --- baocode-dev's public repositories ---

for name in $(gh api "orgs/$ORG/repos" --paginate --jq '.[].name'); do
  [[ " ${KNOWN_REPOS[*]} " == *" $name "* ]] && continue
  info=$(gh api "repos/$ORG/$name" --jq '"\(.description // "")\n\(.license.spdx_id // "无")"')
  issue_title="$ORG 公开了新仓库：$name"
  issue_body="[\`$ORG/$name\`](https://github.com/$ORG/$name) 现在是公开的。

- 描述：$(sed -n 1p <<<"$info")
- 许可证：$(sed -n 2p <<<"$info")"
  [ "$name" = mobile ] && issue_body="$issue_body

这是手机 App 的仓库：手机端开源了。"
  if dry; then
    echo "=== issue: $issue_title"
    echo "$issue_body"
    continue
  fi
  gh label create "$ORG_LABEL" -R "$REPO" --color 1d76db --description "上游组织的新仓库" --force >/dev/null
  seen=$(gh issue list -R "$REPO" --label "$ORG_LABEL" --state all --search "$name in:title" \
    --json title --jq "map(select(.title == \"$issue_title\")) | length")
  [ "$seen" -eq 0 ] && gh issue create -R "$REPO" --label "$ORG_LABEL" --title "$issue_title" --body "$issue_body"
done
