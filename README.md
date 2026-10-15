# actions

Shared GitHub Actions for versioning and releasing my repositories from [Conventional Commits](https://www.conventionalcommits.org/), so every repository follows the same rules.

| Action | What it does |
|---|---|
| [`version`](version/action.yml) | The next release version, and a release-candidate name for the current commit |
| [`release-notes`](release-notes/action.yml) | Markdown release notes, grouped by commit type, each entry linking its PR |

Both need a full-history checkout (`fetch-depth: 0`).

## Usage

```yaml
- uses: actions/checkout@<sha> # v7
  with:
    fetch-depth: 0

- id: version
  uses: vehkiya/actions/version@<sha> # vX.Y.Z
  with:
    tag-prefix: v # "" for tags like 1.2.3

- uses: vehkiya/actions/release-notes@<sha> # vX.Y.Z
  with:
    previous-tag: ${{ steps.version.outputs.previous-tag }}
    tag: ${{ steps.version.outputs.version-tag }}

- run: gh release create "${{ steps.version.outputs.version-tag }}" --notes-file release-notes.md
```

Pin both actions to the same commit SHA; Renovate's `helpers:pinGitHubActionDigests` keeps them current.

## Version rules

| Commit | Bump |
|---|---|
| `type!:`, or a `BREAKING CHANGE:` / `BREAKING:` footer | major |
| `feat:` | minor |
| `docs:`, `test:` | none |
| every other type (`fix:`, `refactor:`, `chore:`, `ci:`, …) | patch |

`version` outputs:
- `version`, `version-tag`, and `version-type`. `version-type` is `none` when there's nothing to release.
- `previous-tag`.
- `rc-version` (`X.Y.Z-rc.N`, where N counts the commits since the last release) and `commit-tag` (`sha-<commit>`), for release candidates.

## Release notes

```
## 💥 Breaking changes   type!: or a BREAKING CHANGE: / BREAKING: footer
## 🚀 Features           feat
## 🐛 Bug fixes          fix
## 👷 CI                 ci
## 📦 Others             everything else, docs: and test: included
```

- **Entries:** each entry is `type(scope): subject #PR`, oldest first, and empty sections are left out. The notes end with a **Full Changelog** compare link.
- **Finding the PR:** the PR number comes from the `(#N)` a squash merge adds to the subject. For a rebase merge, the action looks the PR up on GitHub using `token`, which defaults to the workflow's token. A commit pushed without a PR links the commit itself.

## Development

```bash
tests/release-notes.test.sh
shellcheck release-notes/release-notes.sh tests/*.sh
```

Every push to `main` that warrants a new version is released automatically as `vX.Y.Z` (`.github/workflows/cd.yml`).
