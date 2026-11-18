#!/usr/bin/env bash
set -euo pipefail

# Starts a release of Coder Desktop: checks the version and the commit, then dispatches the
# release workflow on main. Nobody pushes the vX.Y.Z tag: the run creates it once another
# release manager approves it. See RELEASING.md.
#
# The checks here are the workflow's own, repeated so that a mistake shows before the run
# asks anyone for approval. The workflow is what enforces them.
#
# Requires: git, and gh logged in to an account with write access to the repository.

REPO="coder/coder-desktop-macos"
REMOTE_URL="https://github.com/$REPO.git"
WORKFLOW="release.yml"

usage() {
  echo "Usage: $0 [--commit <commit>] [--notes-file <file>] [--dry-run] <version>"
  echo "  <version>            Version to release, e.g. v0.8.7"
  echo "  --commit <commit>    Commit on main to release (default: the head of main)"
  echo "  --notes-file <file>  Read the release notes from <file> instead of opening an editor"
  echo "  --dry-run            Run the checks and show the release, without starting it"
  echo "  -h, --help           Display this help message"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

VERSION=""
COMMIT=""
NOTES_FILE=""
DRY_RUN=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --commit)
      [[ "$#" -ge 2 ]] || die "--commit needs a value"
      COMMIT="$2"
      shift 2
      ;;
    --notes-file)
      [[ "$#" -ge 2 ]] || die "--notes-file needs a value"
      NOTES_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown parameter passed: $1"
      usage
      exit 1
      ;;
    *)
      [[ -z "$VERSION" ]] || die "Only one version can be released at a time"
      VERSION="$1"
      shift
      ;;
  esac
done

[[ -n "$VERSION" ]] || {
  usage
  exit 1
}
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "The version must look like v1.2.3, got '$VERSION'"
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || die "No such file: $NOTES_FILE"

command -v gh >/dev/null || die "gh is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run 'gh auth login'"

# The notes file may be a relative path, so resolve it before changing directory.
if [[ -n "$NOTES_FILE" ]]; then
  NOTES_FILE="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"
fi
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# From GitHub and not from a remote of this clone, which may be a fork or out of date.
git fetch --quiet "$REMOTE_URL" refs/heads/main
main_head="$(git rev-parse FETCH_HEAD)"
git fetch --quiet "$REMOTE_URL" 'refs/tags/v*:refs/tags/v*'

commit="$(git rev-parse --verify --quiet "${COMMIT:-$main_head}^{commit}")" ||
  die "'$COMMIT' is not a commit in this clone"
git merge-base --is-ancestor "$commit" "$main_head" ||
  die "$commit is not on main. Merge it through a pull request first"

tag_exists=false
if existing="$(git rev-parse --verify --quiet "refs/tags/$VERSION^{commit}")"; then
  [[ -n "$(git ls-remote --tags "$REMOTE_URL" "refs/tags/$VERSION")" ]] ||
    die "Tag $VERSION exists in this clone but not on GitHub. The release run creates the tag: delete yours with 'git tag -d $VERSION'"
  [[ "$existing" == "$commit" ]] || die "Tag $VERSION already exists at $existing, not at $commit"
  tag_exists=true
fi

tags="$(git tag --list 'v*' --sort=-version:refname)"
latest="$(grep -E -m 1 '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$tags" || true)"
if [[ "$tag_exists" == false ]]; then
  # scripts/version.sh reads the version from the tag on the commit, so each release needs a
  # commit of its own.
  released="$(git tag --points-at "$commit" --list 'v*' | paste -sd ' ' -)"
  [[ -z "$released" ]] || die "$commit was already released as $released. Release a newer commit"

  # Versions only go up, and a release never comes from before the last one.
  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest" "$VERSION" | sort -V -C ||
      die "$VERSION is not newer than $latest, the latest release"
    git merge-base --is-ancestor "$latest" "$commit" ||
      die "$commit is older than the commit released as $latest"
  fi
fi

# Every push to main publishes a preview build and rewrites the appcast, and so does a release.
# Two runs doing that at once can lose one of the two updates.
running="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --branch main --event push \
  --json status,url --jq '.[] | select(.status != "completed") | .url')"
[[ -z "$running" ]] || die "A preview build is still running. Wait for it to finish: $running"

# A commit whose preview build failed will likely fail as a release too, after it is tagged.
preview="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --branch main --event push \
  --commit "$commit" --limit 1 --json conclusion --jq '.[0].conclusion // empty')"

notes=""
if [[ -n "$NOTES_FILE" ]]; then
  notes="$(<"$NOTES_FILE")"
elif [[ "$DRY_RUN" == false ]]; then
  notes_file="$(mktemp)"
  trap 'rm -f "$notes_file"' EXIT
  # Through sh, as git does, because the variable may hold a command with arguments, like
  # "code --wait".
  sh -c "${VISUAL:-${EDITOR:-vi}} \"\$1\"" -- "$notes_file"
  notes="$(<"$notes_file")"
fi
if [[ -n "$NOTES_FILE" || "$DRY_RUN" == false ]]; then
  [[ -n "${notes//[[:space:]]/}" ]] || die "The release notes are empty"
fi

echo "Release $VERSION of $REPO"
echo "  Commit:            $commit"
echo "                     $(git log -1 --format='%s (%cs)' "$commit")"
echo "  Latest release:    ${latest:-none}"
echo "  Preview build:     ${preview:-none found for this commit}"
if [[ "$tag_exists" == true ]]; then
  echo "  Tag:               $VERSION already exists at this commit. The run will use it"
fi
if [[ -n "$notes" ]]; then
  echo "  Release notes:"
  while IFS= read -r line; do
    echo "    $line"
  done <<<"$notes"
fi
echo

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run: nothing was started."
  exit 0
fi

answer=""
read -r -p "Start the release? [y/N] " answer || true
[[ "$answer" =~ ^[Yy]$ ]] || {
  echo "Nothing was started."
  exit 0
}

gh workflow run "$WORKFLOW" --repo "$REPO" --ref main \
  -f version="$VERSION" -f commit="$commit" -f release_notes="$notes" -f dryrun=false

echo
echo "The release run has started:"
echo "  https://github.com/$REPO/actions/workflows/$WORKFLOW?query=event%3Aworkflow_dispatch"
echo "It now waits for a release manager other than you to approve it. Once approved, it creates"
echo "the tag $VERSION, then builds, signs and publishes the release. See RELEASING.md."
