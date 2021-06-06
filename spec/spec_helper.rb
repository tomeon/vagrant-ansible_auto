# frozen_string_literal: true

require 'pathname'

type = if File.basename($PROGRAM_NAME) == 'vagrant-spec'
         'acceptance'
       else
         'unit'
       end

RSpec.configure do |config|
  config.pattern    = "#{type}/**/*_spec.rb"
  config.color      = true
  config.formatter  = 'documentation'
  config.order      = 'rand'
end

Pathname.new(__FILE__).tap do |helper|
  $LOAD_PATH.unshift((helper.parent.parent + 'lib').to_s)

  require 'vagrant/ansible_auto'

  if (support_dir = helper.parent.join('support', type)).directory?
    support_dir.find { |f| require f if f.extname == '.rb' }
  end
end

if type == 'unit'
  ENV['VAGRANT_DISABLE_PLUGIN_INIT'] = 'yes'
  ENV['VAGRANT_NO_PLUGINS'] = 'yes'

  require 'simplecov'
  SimpleCov.start unless SimpleCov.running
end
