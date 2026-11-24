cask "tiebapure-mac" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/yamakze/TiebaPure-Mac/releases/download/v#{version}/TiebaPure-Mac-#{version}.zip"
  name "TiebaPure-Mac"
  desc "Native macOS client for Baidu Tieba"
  homepage "https://github.com/yamakze/TiebaPure-Mac"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "TiebaPure-Mac.app"
end
