# frozen_string_literal: true

source 'https://rubygems.org'

group :development do
  gem 'pry'
  gem 'vagrant', github: 'hashicorp/vagrant', tag: 'v2.4.9'
  gem 'vagrant-spec', github: 'hashicorp/vagrant-spec', ref: 'ff6dbeb'
  # Needed by vagrant-spec; no longer bundled with Ruby as of 3.0.
  gem 'webrick'
end

group :plugins do
  gemspec
end
