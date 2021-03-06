module WebpackerHelpers
  PACKS_DIRECTORY =  File.expand_path("../../#{DUMMY_LOCATION}/public/packs", __FILE__)
  begin
    MAJOR, MINOR, PATCH, _ = Bundler.locked_gems.specs.find { |gem_spec| gem_spec.name == 'webpacker' }.version.segments
  rescue
    MAJOR, MINOR, PATCH, _ = [0,0,0]
  end

  module_function
  def available?
    defined?(Webpacker)
  end

  def when_webpacker_available
    if available?
      yield
    end
  end

  def compile
    return unless available?
    clear_webpacker_packs
    Dir.chdir("./test/#{DUMMY_LOCATION}") do
      # capture_io do
        Rake::Task['webpacker:compile'].reenable
        Rake::Task['webpacker:compile'].invoke
      # end
    end
    # Reload cached JSON manifest:
    manifest_refresh
  end

  def compile_if_missing
    unless File.exist?(PACKS_DIRECTORY)
      compile
    end
  end

  def clear_webpacker_packs
    FileUtils.rm_rf(PACKS_DIRECTORY)
  end

  if MAJOR < 3
    def manifest_refresh
      Webpacker::Manifest.load
    end
  else
    def manifest_refresh
      Webpacker.manifest.refresh
    end
  end

  if MAJOR < 3
    def manifest_lookup name
      Webpacker::Manifest.load(name)
    end
  else
    def manifest_lookup _
      Webpacker.manifest
    end
  end

  if MAJOR < 3
    def manifest_data
      Webpacker::Manifest.instance.data
    end
  else
    def manifest_data
      Webpacker.manifest.refresh
    end
  end

  # Start a webpack-dev-server
  # Call the block
  # Make sure to clean up the server
  def with_dev_server
    # Start the server in a forked process:
    webpack_dev_server = Dir.chdir("test/#{DUMMY_LOCATION}") do
      spawn 'RAILS_ENV=development ./bin/webpack-dev-server '
    end

    detected_dev_server = false

    # Wait for it to start up, make sure it's there by connecting to it:
    30.times do |i|
      begin
        # Make sure that the manifest has been updated:
        manifest_lookup("./test/#{DUMMY_LOCATION}/public/packs/manifest.json")
        example_asset_path = manifest_data.values.first
        if example_asset_path.nil?
          # Debug helper
          # puts "Manifest is blank, all manifests:"
          # Dir.glob("./test/#{DUMMY_LOCATION}/public/packs/*.json").each do |f|
          #   puts f
          #   puts File.read(f)
          # end
          next
        end
        # Make sure the dev server is up:
        if MAJOR < 3
          file = open('http://localhost:8080/packs/application.js')
          if !example_asset_path.start_with?('http://localhost:8080') && ! file
            raise "Manifest doesn't include absolute path to dev server"
          end
        else
          # Webpacker proxies the dev server when Rails is running in Webpacker 3
          #  so the manifest doens't have absolute paths anymore..
          # Reload webpacker config.
          old_env = ENV['NODE_ENV']
          ENV['NODE_ENV'] = 'development'
          Webpacker.instance.instance_variable_set(:@config, nil)
          Webpacker.config
          running = Webpacker.dev_server.running?
          ENV['NODE_ENV'] = old_env
          raise "Webpack Dev Server hasn't started yet" unless running
        end

        detected_dev_server = true
        break
      rescue StandardError => err
        puts err.message
      ensure
        sleep 0.5
        # debug counter
        # puts i
      end
    end

    # If we didn't hook up with a dev server after waiting, fail loudly.
    unless detected_dev_server
      raise 'Failed to start dev server'
    end

    # Call the test block:
    yield
  ensure
    # Kill the server process
    # puts "Killing webpack dev server"
    check_cmd = 'lsof -i :8080 -S'
    10.times do
      # puts check_cmd
      status = `#{check_cmd}`
      # puts status
      remaining_pid_match = status.match(/\n[a-z]+\s+(\d+)/)
      if remaining_pid_match
        remaining_pid = remaining_pid_match[1]
        # puts "Remaining #{remaining_pid}"
        kill_cmd = "kill -9 #{remaining_pid}"
        # puts kill_cmd
        `#{kill_cmd}`
        sleep 0.5
      else
        break
      end
    end

    # Remove the dev-server packs:
    WebpackerHelpers.clear_webpacker_packs
    # puts "Killed."
  end
end
