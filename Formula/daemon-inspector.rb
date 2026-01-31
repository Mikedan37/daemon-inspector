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
  homepage "https://github.com/Mikedan37/daemon-inspector"
  url "https://github.com/Mikedan37/daemon-inspector/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "ec957c6661894240e4a9612b0adbe5ef3882371b954f9c71befa73b69525fc7a"
  license "MIT"
  head "https://github.com/Mikedan37/daemon-inspector.git", branch: "main"

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
