class Solet < Formula
  include Language::Python::Virtualenv

  desc "Create and operate local Solet instances"
  homepage "https://solet.ai"
  url "https://github.com/solet-public/homebrew-tap/releases/download/manager-v0.1.0-r25/solet-0.1.0.tar.gz"
  sha256 "be97927511b44389baabb6a389203597899133f56c0bcd8410ae0f0d81b6945a"
  license "Apache-2.0"
  revision 24
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
    ]
    # Homebrew's build sandbox forbids reading the tap checkout while a Formula
    # installs. Render the same reviewed lock bytes into the Formula so the
    # default lock remains non-circular without crossing that sandbox boundary.
    (libexec/"share"/"solet"/"seed.lock.json").write <<~JSON
      {
        "schema_version": 1,
        "repository": "https://github.com/solet-public/macos-bizops.git",
        "release_tag": "release-2026-09-08",
        "commit": "9f3cfa3df57c197e68f541ffad4dd4d14192f953",
        "tree_hash": "2a15d42d26584ef74a9439be73f1c39dbfa02a35",
        "archive_sha256": "be97927511b44389baabb6a389203597899133f56c0bcd8410ae0f0d81b6945a",
        "profile": "macos-bizops"
      }
    JSON
    # `install_symlink` records a path, not bytes — safe for a source build,
    # where __dir__ resolves to this tap. Do NOT add a `bottle do...end`
    # block without re-solving seed discovery first: a bottle builder's
    # __dir__ would get baked into every user's keg, pointing at a tap path
    # that only exists on the machine that built the bottle.
    (libexec/"share"/"solet").install_symlink Pathname(__dir__).parent/"solet_cli"/"homebrew"/"seeds" => "seeds"
    bin.install_symlink libexec/"bin"/"solet"
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
    assert_path_exists libexec/"share"/"solet"/"contracts"/"macos_setup_flow.json"
    refute_path_exists testpath/"Solets"/"brew-test"
  end
end
