# Homebrew formula for daemon-inspector
# https://github.com/Mikedan37/daemon-background-task-introspection
#
# To install locally:
#   brew install --build-from-source Formula/daemon-inspector.rb
#
# To tap and install:
#   brew tap <user>/daemon-inspector
#   brew install daemon-inspector

class DaemonInspector < Formula
  desc "Read-only forensic tool for macOS daemon behavior"
  homepage "https://github.com/Mikedan37/daemon-background-task-introspection"
  url "https://github.com/Mikedan37/daemon-background-task-introspection/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"
  head "https://github.com/Mikedan37/daemon-background-task-introspection.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build",
           "--disable-sandbox",
           "-c", "release",
           "--arch", Hardware::CPU.arch.to_s
    bin.install ".build/release/daemon-inspector"
  end

  test do
    assert_match "daemon-inspector", shell_output("#{bin}/daemon-inspector --version")
    assert_match "read-only", shell_output("#{bin}/daemon-inspector --help")
  end
end
