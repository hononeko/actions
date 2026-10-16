# actions

Shared GitHub Actions for versioning and releasing my repositories from [Conventional Commits](https://www.conventionalcommits.org/), so every repository follows the same rules.

| Action | What it does |
|---|---|
| [`version`](version/action.yml) | The next release version, and a release-candidate name for the current commit |
| [`release-notes`](release-notes/action.yml) | Markdown release notes, grouped by commit type, each entry linking its PR |
| [`smoke-test`](smoke-test/action.yml) | Boots a container image, waits for an HTTP answer, and checks its status and memory |

`version` and `release-notes` need a full-history checkout (`fetch-depth: 0`).

## Usage

```yaml
- uses: actions/checkout@<sha> # v7
  with:
    fetch-depth: 0

- id: version
  uses: hononeko/actions/version@<sha> # vX.Y.Z
  with:
    tag-prefix: v # "" for tags like 1.2.3

- uses: hononeko/actions/release-notes@<sha> # vX.Y.Z
  with:
    previous-tag: ${{ steps.version.outputs.previous-tag }}
    tag: ${{ steps.version.outputs.version-tag }}

- run: gh release create "${{ steps.version.outputs.version-tag }}" --notes-file release-notes.md
```

Pin both actions to the same commit SHA; Renovate's `helpers:pinGitHubActionDigests` keeps them current.

## Version rules

| Commit | Bump |
|---|---|
| a `!` in the header (`type!:`, `type(scope)!:`), or a `BREAKING CHANGE:` footer line | major |
| `feat:` / `feat(scope):` | minor |
| `docs:`, `test:` | none |
| every other type (`fix:`, `refactor:`, `chore:`, `ci:`, …) | patch |

Only the header's `!` and a footer line starting `BREAKING CHANGE:` (or `BREAKING-CHANGE:`) count as breaking. A body that merely mentions them doesn't.

`version` outputs:
- `version`, `version-tag`, and `version-type`. `version-type` is `none` when there's nothing to release.
- `previous-tag`.
- `rc-version` (`X.Y.Z-rc.N`, where N counts the commits since the last release) and `commit-tag` (`sha-<commit>`), for release candidates.

## Release notes

```
## 💥 Breaking changes   type!: or a BREAKING CHANGE: footer
## 🚀 Features           feat
## 🐛 Bug fixes          fix
## 👷 CI                 ci
## 📦 Others             everything else, docs: and test: included
```

- **Entries:** each entry is `type(scope): subject #PR`, oldest first, and empty sections are left out. The notes end with a **Full Changelog** compare link.
- **Finding the PR:** the PR number comes from the `(#N)` a squash merge adds to the subject. For a rebase merge, the action looks the PR up on GitHub using `token`, which defaults to the workflow's token. A commit pushed without a PR links the commit itself.

## Smoke test

```yaml
- uses: docker/build-push-action@<sha> # v7
  with:
    load: true
    tags: smoke:amd64

- uses: hononeko/actions/smoke-test@<sha> # vX.Y.Z
  with:
    image: smoke:amd64
    port: "9090"
    path: /healthz
    status: "200" # an extended regex, e.g. 2..|403
    env: |
      SOME_REQUIRED_SETTING=smoke
    max-memory-mib: "32"
```

It fails when the container exits or doesn't answer within `timeout` seconds (10), when the status doesn't match, or when it uses more than `max-memory-mib` (64) after startup. `started-regex` picks the app's own startup time out of its logs for the report.

## Development

```bash
tests/release-notes.test.sh
shellcheck release-notes/release-notes.sh smoke-test/smoke-test.sh tests/*.sh
```

Every push to `main` that warrants a new version is released automatically as `vX.Y.Z` (`.github/workflows/cd.yml`).
