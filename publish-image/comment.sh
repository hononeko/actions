#!/usr/bin/env bash
# Adds or updates the one comment on a pull request that names its latest published image.
#
# Usage: comment.sh <pr-number> <image-reference>
#   GITHUB_REPOSITORY  owner/repo
#   GH_TOKEN           a token that may write pull request comments
#   COMMENT_TITLE      heading of the comment (default "Image published")
#   COMMENT_NOTE       optional line added under the reference
#
# The comment is found again by a hidden marker, so every push updates it instead of adding another one.
set -euo pipefail

pr=${1:?usage: comment.sh <pr-number> <image-reference>}
ref=${2:?usage: comment.sh <pr-number> <image-reference>}
[[ $pr =~ ^[1-9][0-9]*$ ]] || { echo "::error title=publish-image::'$pr' isn't a pull request number" >&2; exit 1; }
marker='<!-- hononeko/actions:publish-image -->'

body="$marker
### ${COMMENT_TITLE:-Image published}

\`\`\`
$ref
\`\`\`"
if [ -n "${COMMENT_NOTE-}" ]; then
  body="$body

$COMMENT_NOTE"
fi

id=$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$pr/comments" \
  --jq "first(.[] | select(.body | startswith(\"$marker\")) | .id) // empty")
id=${id%%$'\n'*}
if [ -n "$id" ]; then
  gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" -f body="$body" >/dev/null
  echo "Updated comment $id on #$pr"
else
  gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$pr/comments" -f body="$body" >/dev/null
  echo "Commented on #$pr"
fi
