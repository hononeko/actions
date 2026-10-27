# actions

Shared GitHub Actions for versioning, releasing and publishing my repositories from [Conventional Commits](https://www.conventionalcommits.org/), so every repository follows the same rules.

| Action | What it does |
|---|---|
| [`version`](version/action.yml) | The next release version, and a release-candidate name for the current commit |
| [`release-notes`](release-notes/action.yml) | Markdown release notes, grouped by commit type, each entry linking its PR |
| [`smoke-test`](smoke-test/action.yml) | Boots a container image, waits for an HTTP answer, and checks its status and memory |
| [`bun-setup`](bun-setup/action.yml) | Installs a pinned Bun version and the dependencies locked in `bun.lock`, with a cache |
| [`gradle-setup`](gradle-setup/action.yml) | Installs a pinned JDK and sets up the project's Gradle wrapper, validated and with a cache |
| [`publish-image`](publish-image/action.yml) | Joins per-architecture images pushed by digest into one multi-arch image under the given tags, and attests it |
| [`prune-snapshots`](prune-snapshots/action.yml) | Deletes a pull request's snapshot images from GHCR when it closes |
| [`lint-go`](lint-go/action.yml) | Checks `go.mod` is tidy and runs golangci-lint |
| [`lint-kotlin`](lint-kotlin/action.yml) | Runs the detekt CLI, optionally with its ktlint rules, without a Gradle plugin |
| [`lint-js`](lint-js/action.yml) | Runs oxlint on JavaScript and TypeScript |
| [`lint-docker`](lint-docker/action.yml) | Runs hadolint on the repository's Dockerfiles |
| [`lint-actions`](lint-actions/action.yml) | Runs actionlint and zizmor on the repository's workflows and actions |
| [`coverage`](coverage/action.yml) | Reports Go, JaCoCo/Kover or lcov coverage, overall and on a pull request's changed lines, with minimums |

`version` and `release-notes` need a full-history checkout (`fetch-depth: 0`).

A repository that releases several things from one tree, such as one image per directory, gives each its own `tag-prefix` and passes `change-path` to both, so only the commits under that path count toward its version and appear in its notes:

```yaml
- id: version
  uses: hononeko/actions/version@v1
  with:
    tag-prefix: my-image- # my-image-1.2.3
    change-path: images/my-image

- uses: hononeko/actions/release-notes@v1
  with:
    previous-tag: ${{ steps.version.outputs.previous-tag }}
    tag: ${{ steps.version.outputs.version-tag }}
    change-path: images/my-image
```

## Usage

```yaml
- uses: actions/checkout@<sha> # v7
  with:
    fetch-depth: 0

- id: version
  uses: hononeko/actions/version@v1
  with:
    tag-prefix: v # "" for tags like 1.2.3

- uses: hononeko/actions/release-notes@v1
  with:
    previous-tag: ${{ steps.version.outputs.previous-tag }}
    tag: ${{ steps.version.outputs.version-tag }}

- run: gh release create "${{ steps.version.outputs.version-tag }}" --notes-file release-notes.md
```

### Updates

Use the actions by their major tag, `@v1`. Every release moves it, so a repository runs the latest compatible release as soon as it's out, with no pull request to merge. A breaking change releases a new major (`v2`), which each repository moves to on purpose.

- **Renovate:** `helpers:pinGitHubActionDigests` would pin `@v1` to a commit SHA and open a pull request for every release. Extend this repository's preset, which keeps the tag and only offers a new major:

  ```json
  { "extends": ["github>hononeko/actions//renovate/downstream"] }
  ```

- **zizmor:** its `unpinned-uses` audit wants every action pinned by hash. `lint-actions` allows `hononeko/actions/*` by tag when a repository has no zizmor config of its own; a repository with one adds the same policy:

  ```yaml
  rules:
    unpinned-uses:
      config:
        policies:
          hononeko/actions/*: ref-pin
  ```

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
- With the `pr-number` input, `snapshot-tag` (`pr-<PR>-sha-<commit>`) and `snapshot-version` (`X.Y.Z-pr.<PR>.N`), for [branch snapshots](#branch-snapshots). On `pull_request` events, check out the pull request's head commit (`ref: ${{ github.event.pull_request.head.sha }}`). The action fails on GitHub's merge commit, because that commit isn't on the branch. It compares `HEAD` with the `head-sha` input, which defaults to the pull request's head.

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

- uses: hononeko/actions/smoke-test@v1
  with:
    image: smoke:amd64
    port: "9090"
    path: /healthz
    status: "200" # an extended regex, e.g. 2..|403
    env: |
      SOME_REQUIRED_SETTING=smoke
    max-memory-mib: "32"
```

`image` can also be a registry reference (e.g. an image pushed by digest); it's pulled before timing starts, so `timeout` and the reported time to answer never include the download. It fails when the container exits or doesn't answer within `timeout` seconds (10), when the status doesn't match, or when it uses more than `max-memory-mib` (64) after startup. `started-regex` picks the app's own startup time out of its logs for the report.

## Bun setup

```yaml
- uses: actions/checkout@<sha> # v7

- id: bun
  uses: hononeko/actions/bun-setup@v1
  # with:
  #   bun-version: 1.4.3      # default: .bun-version, then package.json's "packageManager": "bun@X.Y.Z"
  #   working-directory: app  # default: .
  #   install: "false"        # only install Bun
  #   ignore-scripts: "false" # run lifecycle scripts (only for dependencies you trust)

- run: bun run test
```

- **Pinned:** the version must be exact. `latest`, `1.4` or `^1.4.0` fail with an error naming where the version came from, so builds never float. A leading `v` or `bun-v` and a Corepack `+sha512…` suffix are accepted.
- **Locked:** dependencies are installed with `bun install --frozen-lockfile`, so a `bun.lock` that doesn't match `package.json` fails the job.
- **Lifecycle scripts:** skipped (`--ignore-scripts`) unless `ignore-scripts` is exactly `"false"`.
- **Cache:** `~/.bun/install/cache`, keyed on the OS, architecture, Bun version and `bun.lock`.

Outputs: `bun-version` (the installed version) and `cache-hit` (`"true"` when the cache matched `bun.lock` exactly).

## Gradle setup

```yaml
- uses: actions/checkout@<sha> # v7

- id: gradle
  uses: hononeko/actions/gradle-setup@v1
  # with:
  #   java-version: 25.0.1       # default: .java-version
  #   java-distribution: zulu    # default: a prefix on the version, then temurin
  #   working-directory: app     # default: .
  #   cache-provider: enhanced   # default: basic

- run: ./gradlew check
```

- **Pinned JDK:** either a feature release (`25`), which takes its newest update so security fixes arrive on their own (`check-latest`, not whatever the runner image cached), or an exact version (`25.0.1`; a feature release's first GA is `25.0.0`) for a fully reproducible build. The distribution's full build (`25.0.1+8.0.LTS`) and out-of-band patches (`21.0.4.1`) are accepted too; Temurin publishes those as `21.0.4+101`, so for Temurin pin `21.0.4`, which already takes the newest build of it. `25.0`, `25.x`, `latest` or `26-ea` fail with an error naming where the version came from.
- **Distribution:** `temurin` unless the `java-distribution` input or a prefix on the version names another, the way mise and asdf write `.java-version` (`zulu-25`, `temurin-25.0.1`). It must be one `actions/setup-java` downloads itself; `jdkfile` isn't supported.
- **Pinned Gradle:** the build runs the version the project's wrapper pins in `gradle/wrapper/gradle-wrapper.properties`, and a project without a wrapper fails. A wrapper without `distributionSha256Sum` gets a warning, since the distribution it downloads isn't verified.
- **Validated:** every Gradle wrapper jar in the repository is checked against Gradle's published checksums.
- **Cache:** Gradle User Home, by [`setup-gradle`](https://github.com/gradle/actions/blob/main/docs/setup-gradle.md). Pull requests only read it; the default branch writes it. The cache provider defaults to `basic`, which is open source (MIT) and free for every repository. `enhanced` is Gradle's proprietary library under its own terms.

Outputs: `java-version` (the requested version), `java-distribution`, `java-installed-version` (what was installed, e.g. `25.0.1+8.0.LTS` for a requested `25`), `java-home` (the installed JDK, also exported as `JAVA_HOME`) and `gradle-version` (the wrapper's version).

## Publish image

Each architecture's image is built and pushed by digest in its own job (`docker/build-push-action` with `push-by-digest=true`), and its digest is uploaded as an empty file in a `digests-<arch>` artifact. `publish-image` then joins them:

```yaml
permissions:
  packages: write
  attestations: write # attest: "true" (the default)
  id-token: write # attest: "true"
steps:
  - uses: docker/login-action@<sha> # v4
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}

  - id: publish
    uses: hononeko/actions/publish-image@v1
    with:
      image: ghcr.io/owner/app # lowercase
      tags: |
        ${{ steps.version.outputs.rc-version }}
        ${{ steps.version.outputs.commit-tag }}
      expected-digests: "2" # fail unless both architectures made it
```

- **Checked first:** the image name, every digest and every tag are validated before anything is pushed.
- **Outputs:** `digest`, and `reference` (`<image>:<first tag>@<digest>`, ready to deploy). Both also go to the job summary.
- **Pull request comment:** with `comment-on-pr`, it keeps a single comment on that pull request, updated on every publish, with the latest reference. This needs the `pull-requests: write` permission.

## Branch snapshots

A pull request labelled `snapshot` publishes its branch's image after every push, for testing before merging. Snapshots are tagged `pr-<PR>-sha-<commit>` and `pr-<PR>` (the newest), never as a version, so Renovate never offers one as an update. They're deleted when the pull request closes. The release candidate published from `main` stays the only image that's released.

Snapshot publishing is decoupled into a dedicated `snapshot.yml` workflow for the `labeled` event, keeping `pr.yml` isolated to code changes. If `pr.yml` listens to `labeled`, non-snapshot labels (such as Renovate or triage labels) skip caller jobs, preventing child status checks from being reported in the latest check suite and blocking branch protection.

```yaml
# .github/workflows/pr.yml
on:
  pull_request:
    branches: ["main"]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  plan:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    outputs:
      # Only branches of this repository: a fork's code never runs with a token that can push.
      snapshot: >-
        ${{ github.event.pull_request.head.repo.full_name == github.repository
        && contains(github.event.pull_request.labels.*.name, 'snapshot') }}
      tag: ${{ steps.version.outputs.snapshot-tag }}
      version: ${{ steps.version.outputs.snapshot-version }}
    steps:
      - uses: actions/checkout@<sha> # v7
        with:
          fetch-depth: 0
          ref: ${{ github.event.pull_request.head.sha }}
      - id: version
        uses: hononeko/actions/version@v1
        with:
          pr-number: ${{ github.event.pull_request.number }}

  # The repository's own build: tests, then each architecture's image, smoke-tested and, with push, pushed by digest.
  image:
    needs: plan
    uses: ./.github/workflows/image.yml
    with:
      push: ${{ needs.plan.outputs.snapshot == 'true' }}
      ref: ${{ needs.plan.outputs.snapshot == 'true' && github.event.pull_request.head.sha || '' }}
      version: ${{ needs.plan.outputs.version }}
    permissions:
      contents: read
      packages: write

  snapshot:
    needs: [plan, image]
    if: needs.plan.outputs.snapshot == 'true'
    runs-on: ubuntu-24.04
    permissions:
      packages: write
      attestations: write
      id-token: write
      pull-requests: write
    steps:
      - uses: docker/login-action@<sha> # v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: hononeko/actions/publish-image@v1
        with:
          image: ghcr.io/owner/app
          tags: |
            ${{ needs.plan.outputs.tag }}
            pr-${{ github.event.pull_request.number }}
          expected-digests: "2"
          title: Snapshot
          comment-on-pr: ${{ github.event.pull_request.number }}
          comment-note: For testing only. Deleted when this pull request closes.
```

```yaml
# .github/workflows/snapshot.yml
on:
  pull_request:
    branches: ["main"]
    types: [labeled]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  plan:
    if: github.event.label.name == 'snapshot' && github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    outputs:
      tag: ${{ steps.version.outputs.snapshot-tag }}
      version: ${{ steps.version.outputs.snapshot-version }}
    steps:
      - uses: actions/checkout@<sha> # v7
        with:
          fetch-depth: 0
          ref: ${{ github.event.pull_request.head.sha }}
      - id: version
        uses: hononeko/actions/version@v1
        with:
          pr-number: ${{ github.event.pull_request.number }}

  image:
    needs: plan
    uses: ./.github/workflows/image.yml
    with:
      push: true
      ref: ${{ github.event.pull_request.head.sha }}
      version: ${{ needs.plan.outputs.version }}
    permissions:
      contents: read
      packages: write

  snapshot:
    needs: [plan, image]
    runs-on: ubuntu-24.04
    permissions:
      packages: write
      attestations: write
      id-token: write
      pull-requests: write
    steps:
      - uses: docker/login-action@<sha> # v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: hononeko/actions/publish-image@v1
        with:
          image: ghcr.io/owner/app
          tags: |
            ${{ needs.plan.outputs.tag }}
            pr-${{ github.event.pull_request.number }}
          expected-digests: "2"
          title: Snapshot
          comment-on-pr: ${{ github.event.pull_request.number }}
          comment-note: For testing only. Deleted when this pull request closes.
```

```yaml
# .github/workflows/snapshot-cleanup.yml
on:
  pull_request:
    types: [closed]

jobs:
  prune:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-24.04
    permissions:
      packages: write
    steps:
      - uses: hononeko/actions/prune-snapshots@v1
        with:
          package: app
          pr-number: ${{ github.event.pull_request.number }}
```

- **Building the branch:** the image must be built from `github.event.pull_request.head.sha`, as `image.yml`'s checkout `ref` above. GitHub's default merge commit isn't on the branch.
- **Pruning:** snapshots are tagged with unique snapshot tags (`pr-<PR>` and `pr-<PR>-sha-<commit>`), and `prune-snapshots` deletes package versions matching these snapshot tags, along with their platform images and attestations. Pass `dry-run: "true"` to only log what would be deleted.
- **Running pods:** a pod still running a deleted snapshot keeps its cached copy, but it can't be pulled again. Deploy snapshots only for testing, and go back to a release before the pull request closes.

## Lint

```yaml
lint:
  runs-on: ubuntu-26.04
  permissions:
    contents: read
  steps:
    - uses: actions/checkout@<sha> # v7
      with:
        persist-credentials: false
    - uses: hononeko/actions/lint-actions@v1
    - uses: hononeko/actions/lint-docker@v1
    - uses: hononeko/actions/lint-go@v1
    - uses: hononeko/actions/lint-kotlin@v1
    - uses: hononeko/actions/lint-js@v1
```

Use the ones for the project's languages. Every linter annotates its findings on the pull request and fails the job, so the job can be a required check. Each reads the project's own config, so rules are tuned per repository, in the repository:

| Action | Tool | Config | Inputs |
|---|---|---|---|
| `lint-go` | [golangci-lint](https://golangci-lint.run) | `.golangci.yml` | `working-directory`, `golangci-lint-version`, `only-new-issues`, `tidy`, `args` |
| `lint-kotlin` | [detekt](https://detekt.dev) CLI | `config/detekt/detekt.yml` (on top of detekt's defaults), `config/detekt/baseline.xml` | `working-directory`, `detekt-version`, `config`, `baseline`, `ktlint`, `args` |
| `lint-js` | [oxlint](https://oxc.rs/docs/guide/usage/linter) | `.oxlintrc.json` | `working-directory`, `oxlint-version`, `deny-warnings`, `args` |
| `lint-docker` | [hadolint](https://github.com/hadolint/hadolint) | `.hadolint.yaml` | `dockerfiles`, `failure-threshold`, `config` |
| `lint-actions` | [actionlint](https://github.com/rhysd/actionlint), [zizmor](https://docs.zizmor.sh) | `.github/actionlint.yaml`, `zizmor.yml` | `zizmor-version`, `persona`, `min-severity`, `online-audits`, `actionlint` |

- **Existing findings:** to adopt a linter on a project with findings, accept them once and gate only new ones: a detekt baseline (`detekt --create-baseline`), `only-new-issues: "true"` for golangci-lint, or the tools' ignore comments and config.
- **Pinned:** golangci-lint, detekt and oxlint at exact versions, zizmor at the newest version its pinned action locks by hash, the detekt jars checked against checksums in [`lint-kotlin/checksums.txt`](lint-kotlin/checksums.txt), and the hadolint and actionlint images by digest. Another `detekt-version` runs unverified, with a warning. Renovate keeps the tools and images current; a detekt update needs its jars' checksums added, and CI fails until they are.
- **detekt:** its config format changed in 2.0, so set `detekt-version` to the one the config was written for (`2.0.0-alpha.6` for 2.x). It runs on the runner's JDK 21 when there is one, since its Kotlin compiler may not know the newest JDK. A project that already runs detekt in Gradle can keep doing so.
- **hadolint:** fails from `warning` up by default; `info` and `style` findings are notices. Images pinned as `tag@sha256:…` pass.
- **Without config:** `lint-actions` brings its own. actionlint learns the `ubuntu-26.04` runners, and zizmor skips `self-repository`, whose `uses: $/…` actionlint rejects, and `ref-version-mismatch`, which fails unrelated pull requests whenever an action's major tag moves on before Renovate's digest update merges.

## Coverage

```yaml
- run: go test -coverprofile=coverage.out ./...
# or ./gradlew koverXmlReport | ./gradlew jacocoTestReport | bun test --coverage --coverage-reporter=lcov

- uses: hononeko/actions/coverage@v1
  with:
    files: coverage.out # build/reports/kover/report.xml, **/build/reports/jacoco/test/*.xml, coverage/*/lcov.info
    min-coverage: "80"
    min-changed-coverage: "80"
    comment-on-pr: ${{ github.event.pull_request.number }} # needs pull-requests: write
```

- **Formats:** Go profiles (by statement, as `go tool cover` counts), JaCoCo or Kover XML for Java and Kotlin, and lcov for JS/TS. `format: auto` tells them apart by their first line. Several reports are combined, such as a multi-module build or separate server and client runs, and a line any of them covers is covered. Go profiles can't be combined with the other formats.
- **Changed lines:** on a pull request, the coverable lines it adds or changes, counted from where it branched off `base` (the pull request's base by default), with the uncovered ones listed. Works with full history (`fetch-depth: 0`) or the default shallow checkout of GitHub's merge commit. A shallow checkout of the pull request's head fails, since it can't tell where the branch started. JaCoCo names files by package (`dev/x/Foo.kt`), so they're matched to the repository's files by the end of their paths.
- **Report:** the job summary, and with `comment-on-pr` one comment on the pull request, updated on every push. Each `title` keeps its own comment.
- **Minimums:** `min-coverage` (overall) and `min-changed-coverage` (changed lines) fail the job after reporting. A pull request that changes no coverable line passes `min-changed-coverage`.
- **Outputs:** `coverage`, `covered`, `total`, `changed-coverage`, `changed-covered` and `changed-total`.
- **Kover:** its own totals count a line once per class, so a line shared by several classes (data classes, lambdas) counts more than once there. This action counts each line once, so its figure can differ slightly.

## Development

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

Every push to `main` that warrants a new version is released automatically as `vX.Y.Z` (`.github/workflows/cd.yml`).
