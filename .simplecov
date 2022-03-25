require 'coveralls'
require 'simplecov'

require 'vagrant/ansible_auto'

SimpleCov::Formatter::SilentHTMLFormatter = Class.new(SimpleCov::Formatter::HTMLFormatter).new do
  def silent
    return unless block_given?
    stdout, $stdout = $stdout, StringIO.new
    yield
  ensure
    $stdout = stdout
  end

  def format(result)
    silent { super }
  end
end

SimpleCov.configure do
  add_group     'Sources', 'lib'
  add_group     'Tests', 'spec'
  add_filter    'Vagrantfile*'
  root          VagrantPlugins::AnsibleAuto.source_root.to_s
  coverage_dir  VagrantPlugins::AnsibleAuto.source_root.join('coverage').to_s
end

if ENV.key? 'SIMPLECOV_VAGRANT_ANSIBLE_AUTO_COMMAND_NAME'
  SimpleCov.command_name ENV['SIMPLECOV_VAGRANT_ANSIBLE_AUTO_COMMAND_NAME']

  Coveralls::Output.silent = true

  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::SilentHTMLFormatter,
    Coveralls::SimpleCov::Formatter,
  ])

  SimpleCov.start
else
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    Coveralls::SimpleCov::Formatter
  ])
end
