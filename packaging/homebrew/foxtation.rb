cask "foxtation" do
  version "0.2.1"
  sha256 "ebd026ee6db79ccf5a29c5d493fa2498620b264a826dc2527611a604c62bdaff"

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
