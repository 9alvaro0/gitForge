cask "gitforge" do
  version "1.7.0"
  sha256 "3715285c9243fd6897a96b76bb8d519ecec74f372152a35cfe7a1f38171599ac"

  url "https://github.com/9alvaro0/gitForge/releases/download/v#{version}/gitForge-#{version}.dmg"
  name "gitForge"
  desc "Native Git client built with SwiftUI"
  homepage "https://9alvaro0.github.io/gitForge/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :tahoe"

  app "gitForge.app"

  zap trash: [
    "~/Library/Application Support/gitForge",
    "~/Library/Caches/com.warwarelabs.gitForge",
    "~/Library/HTTPStorages/com.warwarelabs.gitForge",
    "~/Library/Preferences/com.warwarelabs.gitForge.plist",
    "~/Library/Saved Application State/com.warwarelabs.gitForge.savedState",
  ]
end
