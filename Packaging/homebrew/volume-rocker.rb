# Homebrew cask, as published in github.com/printMoney/homebrew-tap (Casks/volume-rocker.rb).
# The release workflow updates `version` and `sha256` there automatically when HOMEBREW_TAP_TOKEN is set.
cask "volume-rocker" do
  version "0.1.2"
  sha256 "8af97fb0ec1516c18623aa8272e7fb547ff8107d0719f6d02bdda5e87a2cd882"

  url "https://github.com/printMoney/volume-rocker/releases/download/v#{version}/VolumeRocker-#{version}.dmg"
  name "Volume Rocker"
  desc "Per-app volume control in the menu bar"
  homepage "https://github.com/printMoney/volume-rocker"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "Volume Rocker.app"

  zap trash: [
    "~/Library/Caches/io.github.printmoney.VolumeRocker",
    "~/Library/HTTPStorages/io.github.printmoney.VolumeRocker",
    "~/Library/Preferences/io.github.printmoney.VolumeRocker.plist",
  ]
end
