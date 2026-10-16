# Solet Homebrew tap

Homebrew tap for [Solet](https://github.com/solet-public/macos-bizops). A
**solet** is a named, persistent agentic service that runs in the background on
your own Mac, with its own PostgreSQL schema, memories, knowledge bases and
plugins. This tap installs the **Solet Manager**, the command that creates and
operates solet instances from the published seed.

**Status (2026-10-16): r71 is published.**
`HOMEBREW_NO_INSTALL_UPGRADE=1 brew install python@3.13 solet-public/tap/solet`
installs manager release `manager-v0.1.0-r71` at formula revision 41, pinned to
seed release `release-2026-10-02-50383f0be56e` of `solet-public/macos-bizops`
at commit `50383f0be56e771183be362300144c975c586ddf`.

Since r43 the install has changed in three ways worth knowing before you start:

- **The model stack is Apple-native on macOS 27** (Core AI embeddings, Apple
  Foundation Models summaries), and `llama.cpp` on macOS 26. Setup provisions
  the models itself in every supported case. The manual LM Studio walkthrough
  that earlier revisions of this page carried is no longer the path.
- **The install command now names `python@3.13`.** From r61 the formula does not
  depend on it and never upgrades it, so a Mac without one needs it installed
  alongside the manager. The upgrade command changed with it.
- **An existing solet can be updated, and a pre-manager clone can be adopted.**
  `solet-manager update` finishes on a solet the manager created (r59) and on a
  plain clone of a listed stable seed after `solet-manager import` (r64, r65).

Every release states its own validation status in its own notes. Read the notes
for the release you are installing rather than assuming this page covers it:
[releases](https://github.com/solet-public/homebrew-tap/releases).

## What you need

- **An Apple silicon Mac.** The manager binary installs on macOS 13 or newer,
  but a fresh `solet create` needs one of the two supported model paths, and
  both are Apple silicon: macOS 27 for the Apple-native stack, or macOS 26 for
  `llama.cpp`. Homebrew ships `llama.cpp` bottles for Apple silicon only, so an
  Intel Mac is not covered by either path today.
- **On macOS 27, Apple Intelligence available.** If it is off, or its own model
  is still downloading, the solet still installs and runs, and summaries stay
  degraded until it becomes available. That condition is a warning and clears
  itself.
- **24 GB of memory or more.** This is the supported minimum, because the solet
  runs a local inference model. An 8 GB or 16 GB machine fails at the models
  stage in a way that looks like a model or manager defect. Check with
  `sysctl -n hw.memsize` before starting and say so plainly if the machine is
  under the floor.
- **About 15 GB of free disk** for the local models plus the instance.
- [Homebrew](https://brew.sh). If you do not have it, install it first from that
  page. This tap ships no installer script and the manager never installs
  Homebrew.
- An account that can install Homebrew casks (Claude Code, Codex, and LM Studio
  if you select it).
- A coding agent to drive the install is strongly recommended: Claude Code or
  Codex. The manager is designed to be driven by an agent that reads JSON output
  and re-runs commands. A person can do it by hand, but it is slower.

## Install in two commands

```console
HOMEBREW_NO_INSTALL_UPGRADE=1 brew install python@3.13 solet-public/tap/solet
solet create <name>
```

Naming `python@3.13` installs it when the Mac has none and marks it installed on
request. `HOMEBREW_NO_INSTALL_UPGRADE=1` leaves an existing one at its version.
When one is already installed, Homebrew prints an `Error:` or `Warning:` line
saying so, exits 0, and installs the manager anyway. That line is expected: do
not treat it as a failure and do not run `brew upgrade python@3.13` because of
it. If the install stops with `No Python 3.13 found`, run the command above
exactly as written.

The two commands are deliberately separate. Homebrew installs only the manager.
`solet create` is its own reviewed transaction: it previews every change it
wants to make to your machine and to the new instance, then asks you to approve
that exact plan. Do not join them with `&&`.

**If Homebrew refuses with `Refusing to load formula solet-public/tap/solet
from untrusted tap`**, that is Homebrew 6's third-party trust check, not a
problem with the formula. Trust this one formula, never the whole tap, and run
the install again:

```console
brew tap solet-public/tap
brew trust --formula solet-public/tap/solet
HOMEBREW_NO_INSTALL_UPGRADE=1 brew install python@3.13 solet-public/tap/solet
```

`brew trust --help` shows the current syntax if yours differs. Older Homebrew
versions have no trust check and install directly.

Pick `<name>` now and use it everywhere. Lowercase, starts with a letter,
letters, digits, `-` and `_` only (`[a-z][a-z0-9_-]{1,62}`). Everything the
solet becomes lives under `~/Solets/<name>`.

## The two commands this formula installs

The formula links both `solet` and `solet-manager`.

- **`solet`** creates and operates an instance the manager created:
  `solet create`, `solet status`, `solet doctor`, `solet start`, `solet list`.
- **`solet-manager`** owns the lifecycle of an instance that already exists:
  `solet-manager update`, `solet-manager import`, `solet-manager inspect`,
  `solet-manager doctor`.

The split matters for a solet you imported rather than created. The `solet`
verbs read a record it does not have, so they refuse with `instance_imported`
and name `solet-manager doctor <name>` instead. The manager has no start verb
either: an imported solet is started by its launchd job, and the refusal names
that command.

## How `solet create` actually behaves

`solet create` is a loop, not a single run. Expect to run it several times. Each
pass does one of two things:

1. **Preview.** `solet create <name> --dry-run --json` probes the machine, works
   out what the next stage needs, and prints a plan. The plan carries an
   `approval_fingerprint` (`sha256:…`) that identifies exactly that plan.
2. **Apply.** `solet create <name> --yes --approval-fingerprint <that value>
   --json` applies the approved plan, and only that plan. If the machine changed
   since the preview, it refuses with `probe_drift` and asks for a fresh
   preview.

The apply step normally exits with code **3** and `"status": "awaiting_user"`.
That is not an error. It means "this stage is done, or needs something from you;
preview again." Read the `message` and `repair` fields: they say which. Then run
the preview again and approve the next plan. Keep going until a preview reports
the flow complete.

Exit codes are a contract: `0` success, `1` a real failure (read `error_kind`
and `evidence`), `2` invalid invocation, `3` awaiting user action. Always pass
`--json`: the human-readable rendering drops fields you need.

The stages, in order: `preflight` → `decision_review` → `system_dependencies`
(Python, Node, PostgreSQL with pgvector, tmux, the Claude Code and Codex
clients) → `genesis` (creates the instance, its database role and Keychain
entries, and the `<name>` command) → `models` (embeddings and summaries) →
`coding_agents` (installs the solet's Claude Code and Codex plugins) →
`optional_accounts` (business connectors, deferred to first use by default) →
`session_sources` (which local coding-agent histories the solet may index) →
`completion` (end-to-end verification).

Decisions the flow cannot make itself come back as `decision_prompts` with a
list of `candidates`. Answer one with `--decision <id>=<value>` on the next
preview, for example `--decision embedding_model=<candidate id>`.

## The models stage

Setup measures the Mac with `sw_vers` and `uname -m` against the same host
profiles the update flow uses, then offers only the choices that Mac can serve.
A choice already recorded for an instance is never re-judged, so a solet keeps
what it was created with even after the Mac is upgraded.

**macOS 27, the recommended path.** Core AI serves the Nomic embeddings and
Apple Foundation Models serve summaries. Setup downloads and verifies a
SHA-256-pinned model archive with a single operator approval. No macOS 27-only
package is installed on any other OS.

**macOS 26.** Core AI has never run on macOS 26, so the Apple choices are
withheld and `llama.cpp` is offered in their place. An explicit Apple selection
is refused with the Mac's version in the message. `system_dependencies`
installs the Homebrew `llama.cpp` formula if `llama-server` is absent, and
`models` writes two host-shared login services, both listening only on
`127.0.0.1`:

| Role | Port | Model | Served as |
| --- | --- | --- | --- |
| Summaries | 18180 | Qwen3 8B Q4_K_M | `qwen3-8b` |
| Embeddings | 18181 | Nomic embed text v1.5 f16 | `nomic-embed-text-v1.5` |

Each model is pinned by Hugging Face revision, size and SHA-256, fetched into
`~/Library/Application Support/Solet/llama.cpp/models/`, and accepted only at
the pinned size and hash. A download resumes from its `.partial` file and
launchd retries the service every 60 seconds. A model still downloading, or
missing, is a **warning rather than a blocked stage**. Setup waits up to ten
minutes for the embeddings server, which the solet needs first, and the 5 GB
summaries model finishes in the background. The embeddings entry declares a
2048-token input budget and the plugin counts every input with the server's own
`/tokenize`, so long text is split to fit rather than truncated.

The embeddings model here is the same Nomic v1.5 build LM Studio serves, so
vectors stay in the same space across the two paths.

**LM Studio, if you select it.** The manager provisions it rather than handing
you instructions: seven operations at the end of `system_dependencies` install
the pinned CLI, start the server with just-in-time loading disabled, pull and
explicitly load both models, and register a shared login job. Each pull has a
900-second deadline and a timeout is retry-safe; preserve `.part` files and
resume with a fresh fingerprint.

Full stage-by-stage detail, the exact pinned artifacts, measured speeds, and
recovery for a release old enough to need manual provisioning are in the seed's
own runbook:
[`09_homebrew_install_troubleshooting_runbook.md`](https://github.com/solet-public/macos-bizops/blob/main/plugins/github_midwife_plugin/knowledge_base/09_homebrew_install_troubleshooting_runbook.md).
Read it before anything is installed; it is the same document the solet can
search for you once it is up.

## Upgrading the manager

Start with the receipt flag, every time:

```console
brew tab --installed-on-request python@3.13 && brew upgrade solet
brew list --versions solet
```

`brew tab` installs and upgrades nothing. It marks `python@3.13` as installed on
request, which stops `brew autoremove`, run by `brew upgrade` during its
periodic cleanup, from deleting the interpreter every solet `.venv` links. A
manager installed before r61 recorded that Python only as its own dependency,
which is exactly the state autoremove collects.

`brew list --versions solet` prints `solet <release>_<formula revision>`, taken
from the archive name, so r71 prints `solet 71_41`.

If a solet's Python does move, its next restart fails every credential read with
`-25293`, because the Keychain ACL of an ad-hoc-signed binary pins its exact
code-directory hash. To recover, in a logged-in GUI session rather than over
SSH, read each Keychain item that solet owns once and answer **Always Allow**,
not Allow. `brew pin python@3.13` prevents your own `brew upgrade` from moving
it and no longer blocks the manager.

## Updating a solet

```console
solet-manager update <name> --dry-run
solet-manager update <name> --yes --approval-fingerprint <fingerprint>
```

The preview lists every planned action and every file it intends to write, and
the fingerprint covers exactly that list. A preview with nothing to do reports
`already_current` and lists no actions.

The update accepts only listed stable releases as starting points, matched
exactly by commit and tree, and refuses anything else with
`predecessor_unsupported` rather than migrating on a guess. Stable seeds from
r43 onward are listed, each bound by commit, tree, provenance and seal stamp.

**A solet created by cloning the seed before the manager existed** is adopted
first:

```console
solet-manager inspect --target <clone> --channel stable --json
solet-manager import --dry-run --json      # then approve, as with every other plan
```

Run `solet-manager import --help` for its exact flags. `inspect` classifies the
clone and reports its `import_disposition`. A clone
sitting exactly on a listed seed is importable. A clone carrying a local commit
or a hand merge on top of one is refused, and the refusal names the newest
listed seed in HEAD's history plus a single realign command: it keeps your
commit on a `solet-pre-import-<sha>` branch, then runs `git reset --mixed`,
which moves HEAD and the index and changes no working file. The clone's origin
must be `solet-public/macos-bizops`.

Two things an update changes that are worth knowing in advance:

- **On macOS 27 it moves Core AI off the GPU.** The GPU path leaks one
  IOSurface per embedding and kills the solet's process at about 16,300 embeds,
  so `compute_preference: gpu` is rewritten to `cpu`. The planned write appears
  in the dry run by its config id, and `solet-manager doctor` names the crash
  risk until it is done. An owner who wants `gpu` sets it again afterwards.
- **A solet whose recorded embedding chunk policy differs from the current one
  takes a one-time catch-up** on its first ledger drain after the update,
  re-embedding events whose stored chunks differ. On a large ledger that takes a
  while. A solet already on the current policy has no catch-up.

Seed releases are append-only commits to `solet-public/macos-bizops`, so a
fast-forward never rewrites what your solet has become.

## Troubleshooting by stage

Everything the manager knows is in the JSON it prints. Before searching
anywhere else, read these fields of the last preview: `message`, `repair`,
`error_kind`, `decision_errors`, `unresolved_actions`, `stage_probe_statuses`,
`adapter_probe_statuses`, `evidence`. Then:

```console
solet status <name> --json       # what the manager believes about the instance
solet doctor <name> --json       # the installation acceptance checks
solet list --json                # every instance the manager created
```

Files worth looking at:

- `~/Solets/<name>` is the instance. Its clone of the seed is there, with the
  seed's own `README.md`, `AGENTS.md` and `CLAUDE.md`.
- `~/.local/state/solet/transactions/<name>.json` is the create transaction
  journal: every stage, action and probe result so far. Read it before
  speculating about what ran.
- `~/Solets/<name>/.solet/install-state.json` is the installed-state projection
  `doctor` reads.
- `~/Solets/<name>/profile/data/logs/` is the solet's own log directory once
  genesis has run. The newest file there is the one to read when the service
  will not come up.
- The background service is a per-user LaunchAgent labelled
  `local.solet.<name>`. `launchctl print gui/$(id -u)/local.solet.<name>` shows
  its state, run count and last exit code.
- `~/Library/Application Support/Solet/llama.cpp/logs/<role>.stderr.log` holds
  the model services' logs on macOS 26, and
  `curl -s http://127.0.0.1:18181/health` answers `{"status":"ok"}` once
  embeddings are serving.

**`preflight` / `decision_review`.** Stops here mean the machine is missing
something basic: no Homebrew, a Python other than 3.13, or a target directory
that already exists. `solet create --target <dir>` refuses a non-empty directory
on purpose; pick another name or move the directory yourself. Never delete a
directory you did not create.

**`system_dependencies`.** PostgreSQL is installed and started with Homebrew,
then pgvector is installed after the server is up. If a probe reports
`postgres_ready` or `pgvector_ready` false, check `brew services list`, then
`psql -U $(whoami) -d postgres -c 'select 1'` and `brew list --versions
pgvector`. `brew services start postgresql@<version>` and re-preview. The
Claude Code and Codex clients are casks and need an account that can install
them; if the cask step refuses, install them yourself with `brew install --cask
claude-code codex` and re-preview.

**`genesis`.** Genesis refuses to reuse a name that has leftover Keychain
entries from an earlier failed attempt, so the new instance does not
crash-loop. If you are retrying a name, delete the Keychain items for service
`<name>-vault` (account `master-key`) and any `<name>.<plugin>` services, with
the operator's approval, or just pick a new name. A LaunchAgent that starts and
immediately exits shows up in `launchctl print` as a growing run count with a
non-zero last exit; read the newest log under `profile/data/logs/`.

**`models`.** On `llama.cpp`, a model warning clears on its own once the
download verifies, and a service stop names its `launchctl` step in `repair`.
On LM Studio, `model_discovery_failed` means nothing answered on
`http://localhost:1234`, and zero candidates with a running server means the
models are absent or not the expected builds.

**`coding_agents`, `session_sources`, `completion`.** These stages run the
solet's own hydration steps: installing its Claude Code and Codex plugins,
registering which local session histories it may index, and running the
end-to-end checks `doctor` reports. They have been exercised less than the
earlier stages on clean machines. If one stops, capture the full preview JSON
and the transaction journal, follow `repair`, and file the two files with your
report.

**If a stage blocks and you want to change a decision**, this release cannot do
it on the same instance name. Re-running `solet create <name>` with different
inputs returns `state_conflict`, and no abandon command exists yet. Create the
instance again under a **new name** with the inputs you want. The host-level
provisioning (Homebrew, PostgreSQL, the models) is reused, and the blocked
instance directory can be removed by hand later.

## Driving the install with a coding agent

Give the agent this page, the seed's `README.md`, and runbook 09. Tell it to:

- run every manager command with `--json` and read the fields above rather than
  guessing;
- treat exit code 3 as "preview again", not as failure;
- stop and ask you before installing casks, editing Keychain entries, or
  deleting anything;
- never run the two install commands joined together, and never fall back to
  cloning the seed and running `bootstrap.py` part-way through a `solet create`
  run. The manual seed path in the seed README is a different route that keeps
  different state; pick one route from the start.

After `completion`, the seed's own hydration runbook takes over
(`plugins/github_midwife_plugin/knowledge_base/01_hydration_runbook.md` inside
`~/Solets/<name>`): it sets up the named Claude Code session launcher, shell
integration and the `<name>` command-line client.

## Known limits

Stated here so nobody discovers them the hard way.

- **An Intel Mac is not covered by either model path.** The Apple-native stack
  needs macOS 27 on Apple silicon, and Homebrew's `llama.cpp` bottles are
  Apple silicon only.
- **A blocked `solet create` cannot be abandoned**, and its decisions cannot be
  changed on the same name (`state_conflict`, no abandon command). Use a new
  name. Fix in design.
- **Reinstalling a name this Mac has used before is not detected for you.** See
  the next section; that sweep is still current practice.
- **`doctor` reports probe checkpoint status from the probe implementations.**
  Its declared expectation values are documentation and are not independently
  evaluated.
- **Per-release validation status lives in the release notes.** A release that
  ships a code path does not necessarily claim a clean-guest measurement of it,
  and the notes say which is which. Read the notes for the release you install.

## Reinstalling on a machine that had a solet

**This is not yet supported, and the manager does not attempt to detect it for
you.** `solet create <name>` on a machine that once held a solet of that name
can silently do the wrong thing rather than failing cleanly:

- If `~/.local/state/solet/transactions/<name>.json` exists, `solet create` can
  resume that old transaction instead of starting fresh, so the new manager
  installs the *old* seed's code under a name that looks like it is running the
  release you just installed (`iss_50db7d43`).
- If `~/.config/solet` still lists the name in its instance registry, `create`
  stops with `state_conflict` and no way to proceed under that name
  (`iss_6e520a72`).
- If the login Keychain still has the old instance's vault entries, genesis
  refuses to re-birth the name rather than overwrite them, and reports the
  stale-vault diagnostic rather than deleting another instance's material for
  you (`iss_74d70ef6`).

Treat any machine that has ever run `solet create <name>`, even a failed or
abandoned attempt, as needing a clean sweep before you try that name again:

```console
launchctl bootout gui/$(id -u)/local.solet.<name> 2>/dev/null || true
launchctl bootout gui/$(id -u)/local.solet.<name>.router 2>/dev/null || true
rm -rf ~/.local/state/solet ~/Solets/<name> ~/.ananta ~/.solet ~/.config/solet
security delete-generic-password -s "<name>-vault" 2>/dev/null || true
# repeat delete-generic-password for every service starting with "<name>."
# that `security dump-keychain | grep <name>` still lists
```

Read back that each path and Keychain item is actually gone (`launchctl print`,
`find`, `security dump-keychain`) before running `solet create <name>` again.
Do not assume the removal succeeded silently.

An existing solet you do not want to touch is unaffected by any of this. A plain
clone created before the manager keeps working, and it now has a route onto the
manager through `solet-manager inspect` and `solet-manager import` rather than a
reinstall.

## Reporting problems

Bug reports are welcome and wanted. File them as issues on
[solet-public/macos-bizops](https://github.com/solet-public/macos-bizops/issues)
with the manager version (`solet --version`), the command, the full JSON it
printed, and the transaction journal. Pull requests are not accepted; a precise
report is worth more. The seed's upstream feedback runbook carries a filing path
that works from an ordinary account with no repository access.

## License

Apache-2.0. See [LICENSE](LICENSE).
