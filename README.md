# Solet Homebrew tap

Homebrew tap for [Solet](https://github.com/solet-public/macos-bizops). A
**solet** is a named, persistent agentic service that runs in the background on
your own Mac, with its own PostgreSQL schema, memories, knowledge bases and
plugins. This tap installs the **Solet Manager**, the command that creates and
operates solet instances from the published seed.

**Status (2026-09-08): the formula is published.** `brew install
solet-public/tap/solet` installs manager release `manager-v0.1.0-r25`
(`solet 0.1.0_24`), pinned to seed release `release-2026-09-08` of
`solet-public/macos-bizops`. The install path has been run end to end on clean
macOS virtual machines up to the point described under *Known gaps* below;
read that section before you start so the one manual step does not surprise
you.

## What you need

- macOS 13 or newer, Apple Silicon or Intel.
- [Homebrew](https://brew.sh). If you do not have it, install it first from
  that page; this tap does not ship an installer script.
- **24 GB of memory or more.** That is the supported minimum, because the
  solet runs a local language model. 8 GB and 16 GB machines will fail at the
  models stage.
- About 15 GB of free disk for the two local models plus the instance.
- An account that can install Homebrew casks (LM Studio, Claude Code, Codex).
- A coding agent to drive the install is strongly recommended: Claude Code or
  Codex. The manager is designed to be driven by an agent that reads JSON
  output and re-runs commands; a person can do it by hand, but it is slower.

## Install in two commands

```console
brew install solet-public/tap/solet
solet create <name>
```

The two commands are deliberately separate. Homebrew installs only the
manager. `solet create` is its own reviewed transaction: it previews every
change it wants to make to your machine and to the new instance, then asks you
to approve that exact plan. Do not join them with `&&`.

**If Homebrew refuses with `Refusing to load formula solet-public/tap/solet
from untrusted tap`**, that is Homebrew 6's third-party trust check, not a
problem with the formula. Trust this one formula (not the whole tap) and run
the install again:

```console
brew tap solet-public/tap
brew trust --formula solet-public/tap/solet
brew install solet-public/tap/solet
```

`brew trust --help` shows the current syntax if yours differs. Older Homebrew
versions have no trust check and install directly.

Pick `<name>` now and use it everywhere. Lowercase, starts with a letter,
letters, digits, `-` and `_` only (`[a-z][a-z0-9_-]{1,62}`). Everything the
solet becomes lives under `~/Solets/<name>`.

## How `solet create` actually behaves

`solet create` is a loop, not a single run. Expect to run it several times.
Each pass does one of two things:

1. **Preview.** `solet create <name> --dry-run --json` probes the machine, works
   out what the next stage needs, and prints a plan. The plan carries an
   `approval_fingerprint` (`sha256:…`) that identifies exactly that plan.
2. **Apply.** `solet create <name> --yes --approval-fingerprint <that value>
   --json` applies the approved plan, and only that plan. If the machine
   changed since the preview, it refuses and asks for a fresh preview.

The apply step normally exits with code **3** and `"status":
"awaiting_user"`. That is not an error. It means "this stage is done, or needs
something from you; preview again." Read the `message` and `repair` fields:
they say which. Then run the preview again and approve the next plan. Keep
going until a preview reports the flow complete.

Exit codes: `0` success, `3` awaiting user action (re-preview or supply what
it asks for), `1` a real failure (read `error_kind` and `evidence`).

The stages, in order: `preflight` → `decision_review` → `system_dependencies`
(Python, Node, PostgreSQL with pgvector, tmux, the Claude Code and Codex
clients) → `genesis` (creates the instance, its database role and Keychain
entries, and the `<name>` command) → `models` (embedding and inference models)
→ `coding_agents` (installs the solet's Claude Code and Codex plugins) →
`optional_accounts` (business connectors, deferred to first use by default) →
`session_sources` (which local coding-agent histories the solet may index) →
`completion` (end-to-end verification).

Decisions the flow cannot make itself come back as `decision_prompts` with a
list of `candidates`. Answer one with `--decision <id>=<value>` on the next
preview, for example `--decision embedding_model=<candidate id>`.

## The one manual step in this release: LM Studio

The `models` stage discovers models from a running LM Studio server. **This
release does not install LM Studio or download the models for you.** On a
fresh Mac the preview stops here with:

```json
"error_kind": "decisions_required",
"decision_errors": [{"id": "embedding_model", "error_kind": "model_discovery_failed", ...}]
```

and both `embedding_model` and `inference_model` offer zero candidates. That
is the expected stop, not a broken install. Do the following, then re-run the
preview:

1. Install LM Studio's headless service. This is the route that has been run
   end to end on clean machines; it needs no window and no click:

   ```console
   curl -fsSL https://lmstudio.ai/install.sh | sh
   ~/.lmstudio/bin/lms daemon up
   ~/.lmstudio/bin/lms server start
   ```

   The installer puts `lms` at `~/.lmstudio/bin/lms` and prints the `export
   PATH=...` line to add to your shell; until you do, use the full path. If
   you would rather have the LM Studio desktop app, `brew install --cask
   lm-studio`, open it once, then `~/.lmstudio/bin/lms bootstrap` registers the
   same command. The app's bundled `lms` has failed on machines without an
   interactive session, so prefer the installer above when an agent is
   driving.

2. **Read this before downloading anything.** The moment the server starts,
   `curl -s http://localhost:1234/v1/models` already lists a model named
   `text-embedding-nomic-embed-text-v1.5`. That is LM Studio's bundled build
   and it is the **wrong** one: it passes a name check and produces different
   vectors with no error. The build the solet needs carries an `-embedding`
   suffix and is about 274 MB, not 84 MB.

3. Download the two models from these exact sources:

   ```console
   ~/.lmstudio/bin/lms get "https://huggingface.co/gaianet/Nomic-embed-text-v1.5-Embedding-GGUF" --gguf --yes
   ~/.lmstudio/bin/lms get "https://huggingface.co/lmstudio-community/Qwen3-14B-GGUF@Q4_K_M" --gguf --yes
   ```

   The inference target is **Qwen3 14B at Q4_K_M** (about 9 GB; the
   `owner/repo@QUANT` form of the URL selects the quantization). A pull this
   size can fail at the very start with `Download failed: Timed-out. Please
   try to resume.` Run the identical command again; it resumes from the
   partial file. Expect 20 to 40 minutes on an ordinary connection, and
   trust the file size over the progress line if you are watching it from a
   script. Then check:

   ```console
   ~/.lmstudio/bin/lms ls
   curl -s http://localhost:1234/v1/models
   ```

   `lms ls` must show `text-embedding-nomic-embed-text-v1.5-embedding` at
   roughly 274 MB alongside the Qwen3 14B entry. If you only see the 84 MB
   `text-embedding-nomic-embed-text-v1.5`, the download did not happen.

4. If the server stops answering, `~/.lmstudio/bin/lms server start` again;
   with the desktop app, quit and reopen it first.

5. Load both models so the server reports them, then re-run the preview:

   ```console
   ~/.lmstudio/bin/lms load text-embedding-nomic-embed-text-v1.5-embedding --yes
   ~/.lmstudio/bin/lms load qwen3-14b --context-length 8192 --yes
   ```

   LM Studio derives the served ids from the download sources, so the two
   ids are `text-embedding-nomic-embed-text-v1.5-embedding` and `qwen3-14b`.
   Leave GPU offload at its default on a Mac; add `--gpu off` only inside a
   virtual machine with no GPU. The two decisions now list candidates.
   Approve with the discovered ids, choosing the `-embedding` suffixed nomic
   entry, for example:

   ```console
   solet create <name> --dry-run --json
   solet create <name> --dry-run --json \
     --decision embedding_model=<id from candidates> \
     --decision inference_model=<id from candidates>
   solet create <name> --yes --approval-fingerprint <sha256 from that preview> --json
   ```

   **Status as of 2026-09-08 13:30 UTC.** The embedding decision has been
   verified end to end on a clean 24 GB machine with exactly these steps. The
   inference decision has not. `qwen3-14b` loads and answers, but it is a
   reasoning model that thinks before it replies, and the manager's
   qualification probe currently reports `decision_qualification_failed`
   with zero permitted candidates for `inference_model`. This is being
   treated as a manager defect and is under investigation; expect either a
   hand-fix line here or an updated release. Until then a fresh
   `solet create` stops at the models stage even with both models installed
   and loaded. Do not substitute a different inference model to get past it;
   a solet created that way would not match its seed.

6. Make the server come back after a reboot. In LM Studio, open Settings and
   turn on the option that runs the local server (headless service) at login;
   the wording varies by version. Without it, the solet starts on login but
   cannot embed or think until you start the server by hand. The manager does
   not check this yet.

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
  journal: every stage, action and probe result so far.
- `~/Solets/<name>/.solet/install-state.json` is the installed-state
  projection `doctor` reads.
- `~/Solets/<name>/profile/data/logs/` is the solet's own log directory once
  genesis has run. The newest file there is the one to read when the service
  will not come up.
- The background service is a per-user LaunchAgent labelled `local.solet.<name>`.
  `launchctl print gui/$(id -u)/local.solet.<name>` shows its state, run count
  and last exit code.

**`preflight` / `decision_review`.** Stops here mean the machine is missing
something basic: no Homebrew, a Python other than 3.13, or a target directory
that already exists. `solet create --target <dir>` refuses a non-empty
directory on purpose; pick another name or move the directory yourself.

**`system_dependencies`.** PostgreSQL is installed and started with Homebrew,
then pgvector is installed after the server is up (that ordering was the
defect fixed in this release). If a probe still reports `postgres_ready` or
`pgvector_ready` false, check `brew services list`, then `psql -U $(whoami)
-d postgres -c 'select 1'` and `brew list --versions pgvector`. `brew services
start postgresql@18` (or the version Homebrew installed) and re-preview. The
Claude Code and Codex clients are Homebrew casks and need an account that can
install casks; if the cask step refuses, install them yourself with
`brew install --cask claude-code codex` and re-preview.

**`genesis`.** Genesis refuses to reuse a name that has leftover Keychain
entries from an earlier failed attempt, so the new instance does not crash-loop.
If you are retrying a name, delete the Keychain items for service
`<name>-vault` (account `master-key`) and any `<name>.<plugin>` services, or
just pick a new name. A LaunchAgent that starts and immediately exits shows up
in `launchctl print` as a growing run count with a non-zero last exit; read the
newest log under `profile/data/logs/`.

**`models`.** See the LM Studio section above. `model_discovery_failed` means
no server answered on `http://localhost:1234`; zero candidates with a running
server means the models are not downloaded or not the expected builds.

**`coding_agents`, `session_sources`, `completion`.** These stages run the
solet's own hydration steps: installing its Claude Code and Codex plugins,
registering which local session histories it may index, and running the
end-to-end checks `doctor` reports. They have been exercised less than the
earlier stages on clean machines. If one stops, capture the full preview JSON
and the transaction journal and file them (see below); the `repair` field is
the best available next step.

## Driving the install with a coding agent

Give the agent this page and the seed's `README.md`. Tell it to:

- run every manager command with `--json` and read the fields above rather
  than guessing;
- treat exit code 3 as "preview again", not as failure;
- stop and ask you before installing casks, editing Keychain entries, or
  deleting anything;
- never run the two install commands joined together, and never fall back to
  cloning the seed and running `bootstrap.py` part-way through a `solet
  create` run. The manual seed path in the seed README is a different route;
  pick one route from the start.

After `completion`, the seed's own hydration runbook takes over
(`plugins/github_midwife_plugin/knowledge_base/01_hydration_runbook.md` inside
`~/Solets/<name>`): it sets up the named Claude Code session launcher, shell
integration and the `<name>` command-line client.

## Updating

- The manager: `brew update && brew upgrade solet`.
- An existing solet created from the seed: follow the seed-update runbook in
  the solet's own knowledge base (`<name> call
  service_interface::knowledge_service::search '{"query": "seed update
  runbook", "top_k": 3}'`). Seed releases are append-only commits to
  `solet-public/macos-bizops`, so a fast-forward pull never rewrites what your
  solet has become.

## Known gaps in this release

Stated here so nobody discovers them the hard way:

- The `models` stage needs LM Studio and both models provisioned by hand
  (above). Automating that is the next manager change.
- The inference model does not yet pass the manager's qualification probe
  (`decision_qualification_failed`, zero permitted candidates for
  `inference_model`) even when `qwen3-14b` is loaded and answering, because
  it is a reasoning model and the probe does not budget for its thinking
  tokens. Measured 2026-09-08 on a clean 24 GB machine; under investigation.
  Until it is fixed a fresh install stops at the models stage after the
  embedding decision is accepted.
- Nothing yet makes LM Studio's server start at login; the solet's own
  LaunchAgent does, so after a reboot the solet is up before its models are.
- Stages after `models` have had less clean-machine coverage than the ones
  before it.
- `doctor` reports probe checkpoint status from the probe implementations; its
  declared expectation values are documentation and are not independently
  evaluated.
- Solets created earlier by cloning the seed and running `bootstrap.py` are
  not adopted by the manager (`solet status` will not know about them). They
  keep working and keep updating through the seed-update runbook. Converging
  them onto the manager path is designed but not yet shipped.

## Reporting problems

Bug reports are welcome and wanted. File them as issues on
[solet-public/macos-bizops](https://github.com/solet-public/macos-bizops/issues)
with the manager version (`solet --version`), the command, and the full JSON
it printed. Pull requests are not accepted; a precise report is worth more.

## License

Apache-2.0. See [LICENSE](LICENSE).
