cask "foxtation" do
  version "0.1.0"
  sha256 "0ec296145fe5d8cb15261aa5898a8ed6f70aa685180de896d8b36da4c6537ccc"

  url "https://github.com/khmuhtadin/foxtation/releases/download/v#{version}/Foxtation-#{version}.dmg"
  name "Foxtation"
  desc "Local voice dictation with a fox"
  homepage "https://github.com/khmuhtadin/foxtation"

  depends_on arch: :arm64
  depends_on formula: "uv"
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
