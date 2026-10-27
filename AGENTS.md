# Agent & Contributor Guidelines (`AGENTS.md`)

Shared composite actions consumed by other repositories. Consumers use the major tag (`@v1`), which every release moves, so a change here reaches all of them as soon as it's released. Changes to inputs, outputs or rules must stay backwards compatible. If one can't, it's a `feat!:`, which releases a new major that consumers move to on purpose.

## 1. Quality Gates

Before committing, all of these must pass:

```bash
tests/release-notes.test.sh
tests/bun-setup.test.sh
tests/gradle-setup.test.sh
tests/publish-image.test.sh
tests/snapshot-pattern.test.sh
tests/smoke-test.test.sh
tests/coverage.test.sh
tests/lint-annotations.test.sh
tests/lint-kotlin.test.sh
shellcheck release-notes/release-notes.sh smoke-test/smoke-test.sh bun-setup/resolve-version.sh \
  gradle-setup/*.sh publish-image/*.sh prune-snapshots/*.sh coverage/*.sh lint-*/*.sh tests/*.sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color
uvx zizmor@1.31.1 --config lint-actions/zizmor.yml .
```

## 2. Rules

* **Composite actions only:** each action is a folder with an `action.yml`. Scripts sit next to it and are run through `$GITHUB_ACTION_PATH`.
* **Pinned dependencies:** third-party actions are pinned by commit SHA with a version comment.
* **Inputs through `env`:** never interpolate `${{ inputs.* }}` into `run:` scripts; pass inputs as environment variables.
* **One version rule set:** `version/action.yml` and `release-notes/release-notes.sh` share the breaking-change rule (a `!` in the header, or a `BREAKING CHANGE:` footer line). Change both together, along with the tests.

## 3. Commits & Releases

[Conventional Commits](https://www.conventionalcommits.org/), using the rules in the README. Every push to `main` that warrants a version is released as `vX.Y.Z` with grouped release notes.
