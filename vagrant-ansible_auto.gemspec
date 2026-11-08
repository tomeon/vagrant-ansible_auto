# frozen_string_literal: true

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vagrant/ansible_auto/version'

Gem::Specification.new do |spec|
  spec.name          = 'vagrant-ansible_auto'
  spec.version       = VagrantPlugins::AnsibleAuto::VERSION
  spec.authors       = ['Ignacio Galindo', 'Matt Schreiber']
  spec.email         = ['joiggama@gmail.com', 'tomeon@dogea.red']
  spec.summary       = 'Vagrant plugin for building ansible inventory files.'
  spec.description   = 'Helps defining and building ansible inventory files programatically via configuration and command modules.'
  spec.homepage      = 'https://github.com/joiggama/vagrant-ansible_auto'
  spec.license       = 'MIT'

  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})

  spec.files         = `git ls-files -z`.split("\x0").reject do |file|
    file.start_with?('.') || spec.test_files.include?(file)
  end

  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'cane'
  spec.add_development_dependency 'rake', '>= 10.0'
  spec.add_development_dependency 'rspec', '~> 3.5'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'simplecov', '~> 1.2'
  spec.add_development_dependency 'yard'
end
