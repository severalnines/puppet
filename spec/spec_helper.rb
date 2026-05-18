# spec/spec_helper.rb
require 'puppetlabs_spec_helper/module_spec_helper'
require 'rspec-puppet-facts'

RSpec.configure do |c|
  c.default_facts = {
    'networking' => { 'ip' => '10.10.16.13' },
    'memory'     => { 'system' => { 'total_bytes' => 4294967296 } },
  }
end
