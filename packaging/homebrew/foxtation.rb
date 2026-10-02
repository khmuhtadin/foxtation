cask "foxtation" do
  version "0.1.0"
  sha256 "0ec296145fe5d8cb15261aa5898a8ed6f70aa685180de896d8b36da4c6537ccc"

  url "https://github.com/khmuhtadin/foxtation/releases/download/v#{version}/Foxtation-#{version}.dmg"
  name "Foxtation"
  desc "Local voice dictation for macOS, with a fox"
  homepage "https://github.com/khmuhtadin/foxtation"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64
  depends_on formula: "uv"

  app "Foxtation.app"

  # The app isn't notarized yet; without this macOS refuses to open it.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Foxtation.app"]
  end

  zap trash: [
    "~/Library/Application Support/Foxtation",
    "~/Library/Preferences/com.khmuhtadin.foxtation.plist",
  ]
end
