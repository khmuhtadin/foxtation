cask "foxtation" do
  version "0.3.0"
  sha256 "8be73b2e4531b9c66310ae0490fad3507d989d5c4c207773047da9c50bba5915"

  url "https://github.com/khmuhtadin/foxtation/releases/download/v#{version}/Foxtation-#{version}.dmg"
  name "Foxtation"
  desc "Fast voice dictation for Indonesian and English"
  homepage "https://github.com/khmuhtadin/foxtation"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Foxtation.app"

  # The app isn't notarized yet; without this macOS refuses to open it.
  preflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{staged_path}}/Foxtation.app"]
  end

  zap trash: [
    "~/Library/Application Support/Foxtation",
    "~/Library/Preferences/com.khmuhtadin.foxtation.plist",
  ]
end
