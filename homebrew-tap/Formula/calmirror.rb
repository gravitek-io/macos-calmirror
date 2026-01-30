# Homebrew formula for CalMirror CLI
#
# CalMirror is a calendar event mirroring tool for macOS that creates
# privacy-safe blocker events across calendars using Apple EventKit.
#
# Installation:
#   brew tap gravitek/tap
#   brew install calmirror
#
# Background sync (every 15 minutes via launchd):
#   brew services start calmirror

class Calmirror < Formula
  desc "Calendar event mirroring tool for macOS"
  homepage "https://github.com/gravitek/calmirror"
  url "https://github.com/gravitek/calmirror.git", tag: "v1.0.0"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  # CalMirror requires macOS 14 (Sonoma) or later for EventKit full access API
  on_macos do
    depends_on macos: :sonoma
  end

  def install
    system "swift", "build",
           "--configuration", "release",
           "--disable-sandbox",
           "--product", "calmirror"
    bin.install ".build/release/calmirror"
  end

  # Homebrew services integration for launchd-managed background sync.
  # Runs `calmirror sync` every 15 minutes (900 seconds) as a background
  # interval job. Logs are written to the Homebrew var/log directory.
  #
  # Usage:
  #   brew services start calmirror   # install and load the launchd agent
  #   brew services stop calmirror    # unload the launchd agent
  #   brew services info calmirror    # check agent status
  service do
    run [opt_bin/"calmirror", "sync"]
    run_type :interval
    interval 900
    log_path var/"log/calmirror.log"
    error_log_path var/"log/calmirror.log"
    process_type :background
  end

  def caveats
    <<~EOS
      CalMirror requires Full Calendar Access to read and create events.
      Grant access in: System Settings > Privacy & Security > Calendars

      To start automatic background sync (every 15 minutes):
        brew services start calmirror

      To run a one-time sync manually:
        calmirror sync

      To list available calendars:
        calmirror calendars

      To configure a mirror rule:
        calmirror rules add --source <cal-id> --target <cal-id> --window 30 --label "Busy"
    EOS
  end

  test do
    assert_match "calmirror 1.0.0", shell_output("#{bin}/calmirror version")
  end
end
