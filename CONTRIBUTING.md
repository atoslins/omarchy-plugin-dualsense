# Contributing

## Layout

| Path | What it is |
|---|---|
| `BarWidget.qml`, the other `.qml` and `DualSenseArt.js` | the bar widget and its panel (Quickshell / QtQuick) |
| `bin/dualsense-ctl` | the helper the panel drives: Python 3, standard library only |
| `udev/` | the optional udev rule and its digest-pinned installer |
| `tests/` | unit tests for the helper, the installer, the manifest and the changelog |
| `scripts/` | the release flow below |

The plugin runs straight from its git checkout in
`~/.config/omarchy/plugins/atoslins.dualsense`, so the branch checked out there
is what the bar runs. The shell keeps QML it has already loaded: after changing
a `.qml` file, run `omarchy restart shell`. The helper is a new process on every
call and needs nothing.

## Tests

```bash
python3 -m unittest discover -s tests
```

They need no controller. CI runs them on every push and pull request.

## Branches

`omarchy plugin update` fast-forwards each user's checkout to the tip of
`main`, so **whatever lands on `main` ships**. Work on a branch, open a pull
request if you like, and put it on `main` only as part of a release.

Never rewrite `main` — no force-push, no amending or rebasing commits that are
already there. Updates are fast-forward only, and every user's next
`omarchy plugin update` would stop with "cannot fast-forward".

## Versions

The version lives only in `manifest.json`; `dualsense-ctl --version` reads it
from there. Versions follow [Semantic Versioning](https://semver.org/), where
the public interface is:

- the IPC methods (`omarchy-shell atoslins.dualsense …`);
- the `dualsense-ctl` command line and the JSON of `dualsense-ctl status`;
- the setting keys in `shell.json`;
- the profile file format (`~/.config/dualsense/profile.json`);
- the plugin id, `atoslins.dualsense`.

Removing or renaming any of these, or changing what a value means, is a
**major** release. Anything new that keeps all of them working is **minor**.
Fixes are **patch** releases.

## Changelog

Every user-visible change adds an entry under `## [Unreleased]` in
[CHANGELOG.md](CHANGELOG.md): what changed for the user, and why when that is
not obvious. The changelog and release notes are in English; commit messages
in this repository are in Portuguese.

## Releasing

1. On the branch that holds the release, with the Unreleased notes written:

   ```bash
   scripts/release 1.2.0
   ```

   It refuses a dirty tree or a version that is not newer, moves the
   Unreleased notes under `## [1.2.0] — <today>`, bumps `manifest.json`, runs
   the tests, commits `Release 1.2.0` and creates the annotated tag `v1.2.0`.
   Nothing is pushed.

2. Ship it — `main` fast-forwards to the release commit, together with the tag:

   ```bash
   git push --atomic origin HEAD:main v1.2.0
   ```

   The push is refused if `main` has moved on; merge `main` into the branch and
   cut the release again. Do not squash-merge a release branch: the tag has to
   point at a commit that is on `main`.

3. The tag starts the Release workflow, which checks that it matches
   `manifest.json`, runs the tests and publishes the GitHub release with that
   version's notes from the changelog.
