# Homebrew formula for the standalone, notarized Appshots CLI (`appshotsctl`).
#
# For GUI-less / headless / plugin users who want only the CLI + native MCP
# stdio server, without installing the Appshots.app menu-bar app. The binary
# ships with its own stable TCC identity (CFBundleIdentifier
# ceo.nerd.appshots.cli), so Accessibility / Screen Recording grants persist.
#
# The formula points at the notarized zip produced by Distribution/Scripts/release.sh
# and attached to the version's GitHub Release. On each release, bump `version`
# and refresh `sha256` with the digest of the published zip:
#
#   shasum -a 256 appshotsctl-<version>-arm64.zip
#
# Tap install (once the formula is published):  brew install appshotsctl
class Appshotsctl < Formula
  desc "Standalone CLI + MCP server that sends macOS app context to coding agents"
  homepage "https://github.com/Shahfarzane/appshots"
  version "0.2.0"
  url "https://github.com/Shahfarzane/appshots/releases/download/v#{version}/appshotsctl-#{version}-arm64.zip"
  sha256 "a17c7529c3406f96748fabaccc6b6fe00e434a930fea3b35febfccb6979b3732"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :sequoia # macOS 15+

  def install
    bin.install "appshotsctl"
  end

  test do
    assert_match "appshotsctl", shell_output("#{bin}/appshotsctl --help 2>&1", 0)
  end
end
