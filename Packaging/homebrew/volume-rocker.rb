# Homebrew cask template. Copy it to github.com/printMoney/homebrew-tap as Casks/volume-rocker.rb
# and update `version` and `sha256` for each release (the release notes include the SHA-256).
cask "volume-rocker" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/printMoney/volume-rocker/releases/download/v#{version}/VolumeRocker-#{version}.dmg"
  name "Volume Rocker"
  desc "Per-app volume control in the menu bar"
  homepage "https://github.com/printMoney/volume-rocker"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Volume Rocker.app"

  zap trash: [
    "~/Library/Preferences/io.github.printmoney.VolumeRocker.plist",
    "~/Library/Caches/io.github.printmoney.VolumeRocker",
    "~/Library/HTTPStorages/io.github.printmoney.VolumeRocker",
  ]
end
