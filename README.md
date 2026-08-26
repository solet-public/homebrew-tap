# Solet Homebrew tap

Homebrew tap for [Solet](https://github.com/solet-public/macos-bizops).

## Status: no formula is published here yet

`brew install solet-public/tap/solet` **does not work yet.** This tap exists so
that the install path has a stable, permanent home and a fixed name; the formula
will be published here when it can be published honestly.

A Homebrew formula needs an immutable release asset — a source archive at a fixed
URL with a known SHA-256 checksum. No such asset has been published yet. A formula
pointing at bytes that do not exist would be worse than no formula at all: it
would fail part-way through `brew install`, after Homebrew had already decided the
tap looked usable.

## When the formula lands

```sh
brew install solet-public/tap/solet
```

That single command taps this repository and installs Solet.

## What has to be true first

1. The release-relevant changes land on the upstream default branch.
2. A source archive is built **from that landed commit** — not from a working
   tree — and its SHA-256 is taken from that exact archive.
3. The archive is uploaded as a release asset and verified by re-downloading it.
4. The formula is generated against that URL and checksum and published here.
5. A real install is run on a machine that has never seen this project.

Step 5 is the one that matters. Until it has been done at least once, the
install path is unproven no matter how green the tests look.

## License

Apache-2.0. See [LICENSE](LICENSE).
