# Rakefile - Run with: bundle exec rake <task>
require 'puppetlabs_spec_helper/rake_tasks'
require 'puppet-lint/tasks/puppet-lint'
require 'onceover/rake_tasks'

# Default: run all checks
task default: [:syntax, :lint, :spec]

# Validate syntax of all .pp files
desc 'Validate Puppet manifest syntax'
task :syntax do
  Dir['manifests/**/*.pp'].each do |manifest|
    sh "puppet parser validate #{manifest}"
  end
  puts "\n✅ All manifests passed syntax check\n"
end

# Run rspec tests across all OS combinations
desc 'Run rspec-puppet unit tests'
task :spec

# Lint check
PuppetLint.configuration.send('disable_80chars')
PuppetLint.configuration.send('disable_140chars')

desc 'Run full test suite (syntax + lint + rspec)'
task ci: [:syntax, :lint, :spec] do
  puts "\n✅ All CI checks passed\n"
end
