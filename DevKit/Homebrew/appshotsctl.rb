# Homebrew formula for the standalone, notarized Appshots CLI (`appshotsctl`).
#
# For GUI-less / headless / plugin users who want only the CLI + native MCP
# stdio server, without installing the Appshots.app menu-bar app. The binary
# ships with its own stable TCC identity (CFBundleIdentifier
# ceo.nerd.appshots.cli), so Accessibility / Screen Recording grants persist.
#
# The formula points at the notarized zip produced by DevKit/Scripts/release.sh
# and published to R2 under the appshots channel. Until the first artifact is
# published, the sha256 below is a CLEARLY-MARKED PLACEHOLDER — replace it with
# the real digest of the published zip:
#
#   shasum -a 256 appshotsctl-<version>-arm64.zip
#
# Tap install (once the formula is published):  brew install appshotsctl
class Appshotsctl < Formula
  desc "Standalone CLI + MCP server that sends macOS app context to coding agents"
  homepage "https://github.com/Shahfarzane/appshots"
  version "0.2.0"
  url "https://persist.nerd.ceo/appshots/appshotsctl-#{version}-arm64.zip"
  # PLACEHOLDER sha256 — replace with the digest of the published notarized zip.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
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
