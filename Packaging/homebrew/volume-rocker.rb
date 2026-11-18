# Homebrew cask, as published in github.com/printMoney/homebrew-tap (Casks/volume-rocker.rb).
# The release workflow updates `version` and `sha256` there automatically when HOMEBREW_TAP_TOKEN is set.
cask "volume-rocker" do
  version "0.1.1"
  sha256 "e9cb4ca0fd4c7c3a45d8fd2e8035351f5013637010cae800d29d7306753e5c60"

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
