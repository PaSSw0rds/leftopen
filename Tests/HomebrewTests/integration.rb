# Run with `brew ruby Tests/HomebrewTests/integration.rb`.
# Inspect real Homebrew artifacts and saved metadata; never uninstall anything.
require "cask/cask_loader"
require "tmpdir"
require "stringio"

# Fail immediately if loading or serializing the cask tries to run any command.
%i[run run!].each do |method|
  SystemCommand.define_singleton_method(method) do |*args, **options|
    raise "Unexpected external command during cask inspection"
  end
end

Dir.mktmpdir("leftopen-cask-test-") do |directory|
  config = Cask::Config.new(explicit: { appdir: directory })
  content = File.read(File.expand_path("../../Resources/Homebrew/leftopen.rb", __dir__))
  # Avoid importing the real installed LeftOpen receipt during JSON loading.
  content = content.sub('cask "leftopen"', 'cask "leftopen-package-policy-test"')
  warnings = StringIO.new
  original_stderr = $stderr
  begin
    $stderr = warnings
    cask = Cask::CaskLoader::FromContentLoader.new(content).load(config: config)
    cask.config = config
    expected = [Cask::Artifact::App, Cask::Artifact::Binary, Cask::Artifact::Zap]
    raise "Unexpected executable cleanup artifact" unless cask.artifacts.map(&:class).sort_by(&:name) == expected.sort_by(&:name)
    raise "Legacy Ruby receipt required" if cask.uninstall_flight_blocks?

    # Combine the JSON cask metadata with artifacts saved in the installation tab.
    receipt = cask.to_installed_json_hash.merge(
      "version" => cask.version.to_s, "artifacts" => cask.artifacts_list(uninstall_only: true),
    )
    path = Pathname(directory)/"leftopen-package-policy-test.json"
    path.write(JSON.generate(receipt))
    restored = Cask::CaskLoader::FromAPILoader.new(
      "leftopen-package-policy-test", from_json: JSON.parse(path.read), path: path,
      from_installed_caskfile: true, api_fallback: false,
    ).load(config: config)
    raise "Cleanup artifact in installed receipt" unless restored.artifacts.map(&:class).sort_by(&:name) == expected.sort_by(&:name)
    raise "Uninstall flight block in receipt" if restored.uninstall_flight_blocks?
    raise "Missing complete-removal guidance" unless cask.caveats.to_s.include?("Settings > About > Uninstall LeftOpen")
  ensure
    $stderr = original_stderr
  end
  raise "Cask emitted a deprecation warning: #{warnings.string}" if warnings.string.match?(/deprecated|uninstall_preflight/i)
end
puts "Homebrew package-only artifacts and JSON receipt passed; no cleanup commands executed."
