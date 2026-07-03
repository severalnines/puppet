# Gemfile - Ruby dependencies for Puppet module testing
source 'https://rubygems.org'

group :test do
  gem 'puppet',          ENV['PUPPET_VERSION'] || '~> 8.0'
  gem 'rspec-puppet',    '~> 4.0'
  gem 'rspec-puppet-facts'
  gem 'onceover',        '~> 3.20'
  gem 'puppetlabs_spec_helper', '~> 7.0'
  gem 'puppet-lint',     '~> 4.0'
end
