#!/bin/bash
set -euo pipefail

UPSTREAM=upstream
UPSTREAM_URL=https://github.com/scaleway/scaleway-cli.git
BRANCH=main

if (( $# != 1 )); then
    >&2 echo "Syntax: $0 <tag>"
    exit 1
fi

TAG=$1

# Snap versions must not start with 'v' and may only contain [a-zA-Z0-9.+~-]
# Strip a leading 'v' from the tag (e.g. v2.35.0 -> 2.35.0).
SNAP_VERSION="${TAG#v}"

for cmd in git sed; do
    if ! command -v "$cmd" &> /dev/null; then
        >&2 echo "Required command '$cmd' not found"
        exit 1
    fi
done

# Ensure upstream remote exists
if ! git remote | grep -qx "$UPSTREAM"; then
    echo "Adding remote '$UPSTREAM' -> $UPSTREAM_URL"
    git remote add "$UPSTREAM" "$UPSTREAM_URL"
fi

echo "Fetching $UPSTREAM ..."
git fetch "$UPSTREAM" --tags

# Verify the tag exists on upstream
if ! git ls-remote --tags "$UPSTREAM" | grep -q "refs/tags/${TAG}$"; then
    >&2 echo "Tag '${TAG}' not found on upstream remote"
    exit 1
fi

echo "Checking out $BRANCH"
git checkout "$BRANCH"

echo "Pulling $BRANCH"
git pull origin "$BRANCH"

PRE_MERGE_COMMIT=$(git rev-parse HEAD)

echo "Merging upstream tag ${TAG} into ${BRANCH}"
if ! git merge --no-commit "${TAG}"; then
    unmerged_files=$(git diff --name-only --diff-filter=U)
    if [[ -z "${unmerged_files}" ]]; then
        >&2 echo "Merge failed for a reason other than merge conflicts."
        exit 1
    fi

    non_workflow_conflicts=$(echo "${unmerged_files}" | grep -v '^.github/workflows/' || true)
    if [[ -n "${non_workflow_conflicts}" ]]; then
        >&2 echo "Merge failed due to unexpected conflicts outside of .github/workflows/:"
        >&2 echo "${non_workflow_conflicts}"
        >&2 echo "Aborting merge."
        git merge --abort
        exit 1
    fi

    echo "Conflicts found only in .github/workflows/. Resolving using pre-merge versions..."
fi

# Reset .github/workflows entirely to pre-merge version
git rm -rf .github/workflows
git checkout "${PRE_MERGE_COMMIT}" -- .github/workflows

git commit -m "Merge upstream tag ${TAG}"

# Re-apply our snapcraft files on top (merge may have overwritten them
# if upstream ever adds their own snapcraft.yaml).
echo "Generating snapcraft.yaml for version ${SNAP_VERSION}"
sed "s/VERSION/${SNAP_VERSION}/g" snapbuild/snapcraft.yaml.template > snapcraft.yaml

git add snapcraft.yaml snapbuild/snapcraft.yaml.template
git commit -m "Set snapcraft version to ${SNAP_VERSION} (upstream tag ${TAG})"

echo "Pushing to origin"
git push origin "$BRANCH"

echo "Done. Snap version will be: ${SNAP_VERSION}"
