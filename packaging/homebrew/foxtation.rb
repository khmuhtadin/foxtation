cask "foxtation" do
  version "0.4.2"
  sha256 "43c23021672180b3019a1673f503976a38b2738d3c7ac0b905ea3c9a522e0181"

  url "https://github.com/khmuhtadin/foxtation/releases/download/v#{version}/Foxtation-#{version}.dmg"
  name "Foxtation"
  desc "Voice dictation for Mac in 23 languages"
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
