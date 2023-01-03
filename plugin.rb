require 'bundler'

class RubocopPlugin < Cocov::PluginKit::Run
  def wanted_deps
    config = YAML.load_file('.rubocop.yml')
    return unless config.key? 'require'
    required = config['require']
    required = [required] if required.is_a? String
    required
  end

  def gem_deps(deps)
    return [] unless File.exist? "Gemfile.lock"

    lockfile = Bundler::LockfileParser.new(Bundler.read_file("Gemfile.lock"))

    deps.to_h { |dep| [dep, lockfile.specs.find { |s| s.name == dep }] }
  end

  def wanted_rubocop_version
    return nil unless File.exist? "Gemfile.lock"

    lockfile = Bundler::LockfileParser.new(Bundler.read_file("Gemfile.lock"))

    lockfile.specs.find { |s| s.name == "rubocop" }&.version&.to_s
  end

  def install_from_git(spec)
    target = Dir.mktmpdir
    FileUtils.rm_rf target
    puts "Clonning #{spec.source.uri}"
    begin
      exec("git clone #{spec.source.uri} #{target}")
    rescue Cocov::PluginKit::Exec::ExecutionError => e
      puts "Process git exited with status #{e.status}"
      puts e.stdout
      puts e.stderr
      exit 1
    end
    gemspec_path = ["#{spec.name}.gemspec", "#{spec.name}/#{spec.name}.gemspec"]
      .map { |n| "#{target}/#{n}" }
      .find { |n| File.exist?(n) }

    raise "Could not find gemspec for #{spec.name}" if gemspec_path.nil?

    base_dir = File.dirname(gemspec_path)
    # Remove all built gems (if any)
    Dir["#{base_dir}/*.gem"].each { |f| FileUtils.rm_rf f }

    puts "Building #{spec.name}"
    exec("gem build #{File.basename(gemspec_path)}", chdir: base_dir, env: ENV)

    built_gemspec = Dir["#{base_dir}/*.gem"].first
    raise "Built #{gemspec_path}, but no .gem file found" if built_gemspec.nil?

    puts "Installing #{spec.name} from #{built_gemspec}"
    exec("gem install #{built_gemspec}", chdir: base_dir, env: ENV)
  ensure
    FileUtils.rm_rf target
  end

  COP_MAPPING = {
    "Bundler" => :style,
    "Gemspec" => :style,
    "Layout" => :style,
    "Lint" => :bug,
    "Metrics" => :complexity,
    "Migration" => :bug,
    "Naming" => :style,
    "Security" => :security,
    "Style" => :style,
    "Performance" => :performance,
    "RSpec" => :style,
    "Rails" => :style,
  }.freeze

  COP_OVERRIDE = {
    "Bundler/InsecureProtocolSource" => :security,
  }.freeze

  def run_rubocop
    stdout, stderr = exec2("rubocop -f json --fail-level F", env: ENV, chdir: @workdir)
    JSON.parse(stdout)["files"].each do |file|
      path = file["path"]
      file["offenses"].each do |offense|
        cop_name = offense["cop_name"]
        kind = COP_OVERRIDE.fetch(cop_name) { COP_MAPPING[cop_name] } || :bug

        emit_problem(
          kind: kind,
          file: path,
          line_start: offense["location"]["start_line"],
          line_end: offense["location"]["last_line"],
          message: offense["message"]
        )
      end
    end
  end

  def install_rubocop
    wanted_version = wanted_rubocop_version
    if wanted_version.nil?
      puts "Installing rubocop (latest)"
      exec("gem install rubocop")
    else
      puts "Installing rubocop (#{wanted_version})"
      exec("gem install -v #{wanted_version} rubocop")
    end

    puts "Installed rubocop #{exec("rubocop -v").strip}"
  end

  def run
    install_rubocop

    rubocop_deps = if File.exist? ".rubocop.yml"
      wanted_deps
    else
      []
    end

    gem_deps(rubocop_deps).each do |dep, spec|
      version = spec.nil? ? nil : spec.version.to_s
      puts "Installing #{dep} (Version #{version || "missing from Gemfile.lock"})"
      # How do we install this? Oh lawd.
      if spec.source.is_a? Bundler::Source::Rubygems
        args = ["gem install"]
        args.append("-v", version) if version
        args.append(dep)
        exec(args.join(" "))
      else
        install_from_git(spec)
      end
    end

    puts "Running rubocop..."
    run_rubocop
  end
end

Cocov::PluginKit.run(RubocopPlugin)
