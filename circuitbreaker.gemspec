lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "circuitbreaker/version"

Gem::Specification.new do |spec|
  spec.name          = "circuitbreaker"
  spec.version       = CircuitBreaker::VERSION
  spec.authors       = ["misson20000"]
  spec.email         = ["xenotoad@xenotoad.net"]

  spec.summary       = "Interactive low-level debugging toolkit."
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_dependency "pry"
  spec.add_dependency "hexdump"
  spec.add_dependency "cxxfilt"
  spec.add_dependency "twib"
  spec.add_dependency "crabstone"
  spec.add_dependency "curses"
end
