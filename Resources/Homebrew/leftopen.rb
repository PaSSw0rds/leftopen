cask "leftopen" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/SonghaiFan/leftopen/releases/download/v#{version}/LeftOpen-release.zip"
  name "LeftOpen"
  desc "See what your tools left running on localhost"
  homepage "https://github.com/SonghaiFan/leftopen"

  depends_on macos: :sonoma

  app "LeftOpen.app"
  binary "#{appdir}/LeftOpen.app/Contents/MacOS/leftopen"

  caveats <<~EOS
    For complete removal, use LeftOpen > Settings > About > Uninstall LeftOpen.
    brew uninstall only removes the app and CLI; background services, certificates
    and settings may remain. If already removed, reinstall LeftOpen to run its uninstaller.
  EOS

  zap trash: [
    "~/Library/Saved Application State/app.leftopen.mac.savedState",
  ]
end
