cask "foxtation" do
  version "0.1.2"
  sha256 "1fe31d9f11c9c48748e5ee620736a67991d59af8570fe4f3ab019d581e33e501"

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
