# Releasing

How versions are cut for this project. Small, personal, and honest: the goal is a
tagged history you can point at, not heavy ceremony.

## Versioning

Semantic Versioning (`MAJOR.MINOR.PATCH`). The project is in `0.x`: it works and is used
daily, but behavior and flags still evolve, so treat `0.x` as pre-stable and expect the
occasional breaking change between minor versions. `1.0.0` will mark the point where the
command surface and config keys are considered stable.

## Cutting a release

1. Make sure `main` is green: `zsh -n bin/ai` and `zsh scripts/smoke.sh` both pass.
2. In [CHANGELOG.md](CHANGELOG.md), rename the `[Unreleased]` section to
   `[X.Y.Z] - YYYY-MM-DD` and add a fresh empty `[Unreleased]` above it.
3. Commit: `git commit -am "release: vX.Y.Z"`.
4. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`.
5. Push both: `git push origin main --follow-tags`.
6. Optional GitHub release: `gh release create vX.Y.Z --title vX.Y.Z --notes "<changelog section>"`.

## Where things live

- **What changed** goes in [CHANGELOG.md](CHANGELOG.md) (per release).
- **What might come next** goes in [BACKLOG.md](BACKLOG.md) (non-urgent candidates).
- Nothing secret is ever committed; see the Security section of the [README](README.md).
