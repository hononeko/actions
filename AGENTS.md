# Agent & Contributor Guidelines (`AGENTS.md`)

Shared composite actions consumed by other repositories. A change here reaches every consumer through Renovate, so changes to inputs, outputs or rules must stay backwards compatible. If one can't, it's a `feat!:`.

## 1. Quality Gates

Before committing, all of these must pass:

```bash
tests/release-notes.test.sh
tests/bun-setup.test.sh
tests/gradle-setup.test.sh
shellcheck release-notes/release-notes.sh smoke-test/smoke-test.sh bun-setup/resolve-version.sh gradle-setup/*.sh tests/*.sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color
```

## 2. Rules

* **Composite actions only:** each action is a folder with an `action.yml`. Scripts sit next to it and are run through `$GITHUB_ACTION_PATH`.
* **Pinned dependencies:** third-party actions are pinned by commit SHA with a version comment.
* **Inputs through `env`:** never interpolate `${{ inputs.* }}` into `run:` scripts; pass inputs as environment variables.
* **One version rule set:** `version/action.yml` and `release-notes/release-notes.sh` share the breaking-change rule (a `!` in the header, or a `BREAKING CHANGE:` footer line). Change both together, along with the tests.

## 3. Commits & Releases

[Conventional Commits](https://www.conventionalcommits.org/), using the rules in the README. Every push to `main` that warrants a version is released as `vX.Y.Z` with grouped release notes.
