# Homebrew cask

`Casks/gitforge.rb` is the source of truth for the cask published in the
[`9alvaro0/homebrew-tap`](https://github.com/9alvaro0/homebrew-tap) tap, so users can run:

```bash
brew install --cask 9alvaro0/tap/gitforge
```

## One-time setup

1. Create the public repository `9alvaro0/homebrew-tap` (the `homebrew-` prefix is required).
2. Copy `Casks/gitforge.rb` into it under `Casks/` and push.
3. Verify locally: `brew install --cask 9alvaro0/tap/gitforge && brew audit --cask --online 9alvaro0/tap/gitforge`.

## On every release

After `ship.sh` publishes the GitHub release:

```bash
./scripts/update-cask.sh <version> ../homebrew-tap
git -C ../homebrew-tap push
```

`auto_updates true` tells Homebrew that Sparkle keeps the app current, so
`brew upgrade` won't fight the in-app updater.

The official `homebrew/cask` repository only accepts self-submitted apps once
they are notable (roughly 75+ stars, forks or watchers); until then the tap is
the way to go.
