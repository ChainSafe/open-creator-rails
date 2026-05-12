# Contributing to Open Creator Rails

Thank you for your interest in contributing to Open Creator Rails. This project is MIT-licensed and welcomes contributions from the community.

---

## Prerequisites

Before contributing, make sure you have the following installed:

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- [jq](https://jqlang.org/) (optional — used by some scripts)

---

## Contribution Workflow

### 1. Open or reference a GitHub issue

All contributions must be linked to a GitHub issue. Before starting work:

- Search [existing issues](../../issues) to see if the topic is already tracked.
- If not, [open a new issue](../../issues/new) describing the problem or proposed change.
- Reference the issue number in your pull request.

### 2. Fork the repository

Click **Fork** on the repository homepage to create your own copy under your GitHub account.

### 3. Clone your fork and set up the project

```bash
git clone https://github.com/<your-username>/open-creator-rails.git
cd open-creator-rails
forge install
```

### 4. Create a branch

Work on a dedicated branch. Use a descriptive name:

```bash
git checkout -b feat/my-feature
# or
git checkout -b fix/my-bug-fix
```

### 5. Make your changes

Follow the code style of the existing codebase. Run `forge fmt` before committing to ensure consistent formatting:

```bash
forge fmt
```

### 6. Run test suite locally

Every contribution that introduces new behaviour or fixes a bug must include corresponding tests:

- **New features**: add tests that cover the new code paths.
- **Bug fixes**: add a regression test that would have failed before the fix.

Place tests under the `test/` directory, following the naming and structure conventions of existing test files.

Verify that your new tests run and pass before creating a Pull Request. PRs that add new contract logic without accompanying tests are unlikely to be accepted.

All CI checks must pass before your pull request can be merged. Run the full suite locally first:

```bash
forge build
forge fmt --check
forge test
```

### 7. Commit and push

```bash
git add .
git commit -m "feat: describe your change"
git push origin feat/my-feature
```

### 8. Open a pull request

Open a pull request from your fork's branch targeting **`main`** on the base repository (`ChainSafe/open-creator-rails`).

In the PR description:
- Summarise the change and its motivation.
- Reference the related issue (e.g. `Closes #123`).
- Confirm that all CI checks pass.

---

## CI Requirements

Pull requests must pass the following CI checks before they can be merged:

| Check | Command |
|-------|---------|
| Build | `forge build` |
| Format | `forge fmt --check` |
| Tests | `forge test` |

These checks run automatically via GitHub Actions on every PR targeting `main`.

---

## Code of Conduct

Please be respectful and constructive in all interactions. We aim to maintain a welcoming environment for contributors of all experience levels.

---

## License

By contributing to this repository you agree that your contributions will be licensed under the [MIT License](https://opensource.org/licenses/MIT).
