# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "niconico/version"

Gem::Specification.new do |s|
  s.name        = "niconico"
  s.version     = Niconico::VERSION
  s.authors     = ["Shota Fukumori (sora_h)"]
  s.email       = ["sorah@tubusu.net"]
  s.homepage    = ""
  s.summary     = %q{TODO: Write a gem summary}
  s.description = %q{TODO: Write a gem description}

  s.rubyforge_project = "niconico"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
