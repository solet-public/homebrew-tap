class Solet < Formula
  include Language::Python::Virtualenv

  desc "Create and operate local Solet instances"
  homepage "https://solet.ai"
  url "https://github.com/solet-public/homebrew-tap/releases/download/manager-v0.1.0-r41/solet-0.1.0.tar.gz"
  sha256 "a8bd328076f79559401cd29b0ebc88f13de1a2af185a83b881625cf0e05e24bb"
  license "Apache-2.0"
  revision 27
  depends_on "git"
  depends_on "python@3.13"

  resource "setuptools" do
    url "https://files.pythonhosted.org/packages/95/9c/c510029fc6ef33a6275cd2c5d3cecd6613dfd6aa401d57c54f1c18852ccf/setuptools-84.0.0-py3-none-any.whl"
    sha256 "51a52592b3b99e102b609654876bd65f19f999935166d1352678931132b0c670"
  end

  resource "wheel" do
    url "https://files.pythonhosted.org/packages/2e/29/69cfbb602cd91690c55d38ba9fe53e6a7e76a6fa647bf38f19c138d25449/wheel-0.48.0-py3-none-any.whl"
    sha256 "3217dcc807155e45db462d7ef2431f5ddda0d7273b700d05a67b271ceb1287ab"
  end

  # solet_manager imports packaging.requirements at runtime (the manager's
  # own dependency, not a build-time one — no build backend needs it).
  # Declared in solet_cli/pyproject.toml's dependencies list AND vendored
  # here: this install is --no-deps/--no-index, so pip never consults that
  # declaration to decide what's importable — only what's actually staged
  # into the venv does, which is what this resource provides.
  resource "packaging" do
    url "https://files.pythonhosted.org/packages/df/b2/87e62e8c3e2f4b32e5fe99e0b86d576da1312593b39f47d8ceef365e95ed/packaging-26.2-py3-none-any.whl"
    sha256 "5fc45236b9446107ff2415ce77c807cee2862cb6fac22b8a73826d0693b0980e"
  end

  def install
    venv = virtualenv_create(libexec, "python3.13")
    # Homebrew's python@3.13 provisions pip and wheel via ensurepip but never
    # setuptools (measured: its post-install log installs only pip, wheel).
    # solet_cli's build backend is setuptools.build_meta, so build_isolation
    # below needs setuptools present without hitting the network — vendor it
    # as a pinned, checksummed resource instead of assuming the machine has
    # one lying around.
    venv.pip_install resources
    venv.pip_install buildpath/"solet_setup_contracts", build_isolation: false
    venv.pip_install buildpath/"solet_cli", build_isolation: false

    (libexec/"share"/"solet"/"contracts").install Dir[
      "plugins/github_midwife_plugin/knowledge_base/macos_setup_flow.json",
      "plugins/github_midwife_plugin/knowledge_base/setup_flow.schema.json",
      "plugins/github_midwife_plugin/knowledge_base/setup_answers.schema.json",
      "plugins/github_midwife_plugin/knowledge_base/setup_journal.schema.json",
      "plugins/github_midwife_plugin/knowledge_base/setup_adapter_envelope.schema.json",
      "plugins/github_midwife_plugin/knowledge_base/permissions_manifest.json",
      "plugins/github_midwife_plugin/knowledge_base/existing_install_flow.schema.json",
    ]
    # Homebrew's build sandbox forbids reading the tap checkout while a Formula
    # installs. Render the same reviewed lock bytes into the Formula so the
    # default lock remains non-circular without crossing that sandbox boundary.
    (libexec/"share"/"solet"/"seed.lock.json").write <<~JSON
      {
        "schema_version": 3,
        "channel_id": "stable",
        "repository": "https://github.com/solet-public/macos-bizops.git",
        "release_tag": "release-2026-09-16-5c5aec1965be",
        "commit": "fa2fd84cd35aa686d9e3f62bf320be7b03fb918f",
        "tree_hash": "412a332b2f4d450dcab3ffa9359c314c889fb706",
        "archive_sha256": "a8bd328076f79559401cd29b0ebc88f13de1a2af185a83b881625cf0e05e24bb",
        "profile": "macos-bizops",
        "provenance": {"bundle_name":"macos-bizops","manifest_sha256":"6568475bc5c6446aaed7a34bca754342367751c20c9ccde7dd3158697224714b","origin_id":"31bfa93c-fe20-4988-b019-f8186684e88e","platform":"local","provenance_sha256":"e9d7067b0353ae166ee25f63731bf5c328dc9a1917f7ad5ba47944703239723f","schema_version":1,"seed_id":"1bc2c884-a3d1-5b29-ac87-ffa0ac229033","source_commit":"5c5aec1965befd824b71ad66458ee70025c2d2a7","source_date":"2026-09-16T08:14:05-07:00"},
        "existing_install_contract": {"bundle_digest":"sha256:3c11ed6160768640de96b3d60feebff4fe78386d2e4c4fdd4df075da15dd7801","flow_id":"existing-install","flow_schema_version":1},
        "allowed_repository_migrations": []
      }
    JSON
    # This installed receipt distinguishes a worktree-payload experiment from
    # a published manager/seed pair.  It is deliberately independent of the
    # seed lock: the latter authenticates the seed, while this records how the
    # manager archive itself reached this keg.
    (libexec/"share"/"solet"/"install-source.json").write <<~JSON
      {
        "schema_version": 1,
        "mode": "release",
        "source_commit": "5c5aec1965befd824b71ad66458ee70025c2d2a7"
      }
    JSON
    # `install_symlink` records a path, not bytes — safe for a source build,
    # where __dir__ resolves to this tap. Do NOT add a `bottle do...end`
    # block without re-solving seed discovery first: a bottle builder's
    # __dir__ would get baked into every user's keg, pointing at a tap path
    # that only exists on the machine that built the bottle.
    (libexec/"share"/"solet").install_symlink Pathname(__dir__).parent/"solet_cli"/"homebrew"/"seeds" => "seeds"
    bin.install_symlink libexec/"bin"/"solet"
    bin.install_symlink libexec/"bin"/"solet-manager"
  end

  def caveats
    <<~EOS
      Next: run solet create
    EOS
  end

  test do
    ENV["HOME"] = testpath
    ENV["SOLET_HOME"] = testpath/"manager"
    invalid = testpath/"invalid.toml"
    invalid.write "schema_version = 1\nname = 'brew-test'\nunknown = true\n"
    assert_match "unknown", shell_output("#{bin}/solet create --config #{invalid} --dry-run --json 2>&1", 2)

    listed = shell_output("#{bin}/solet list --json")
    assert_match '"kind": "instance_list"', listed
    assert_match '"instances": []', listed

    preview = shell_output(
      "#{bin}/solet create brew-test --target #{testpath}/Solets/brew-test " \
      "--decision inference_implementation=none --dry-run --json",
    )
    assert_match '"kind": "create_preview"', preview
    assert_match '"status": "preview_ready"', preview
    assert_match '"dry_run_writes": 0', preview
    assert_path_exists libexec/"share"/"solet"/"seed.lock.json"
    assert_path_exists libexec/"share"/"solet"/"install-source.json"
    assert_path_exists libexec/"share"/"solet"/"contracts"/"macos_setup_flow.json"
    refute_path_exists testpath/"Solets"/"brew-test"
  end
end
