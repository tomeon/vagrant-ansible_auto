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
  # SimpleCov 1.x skips spec/ by default; keep reporting on it as before.
  remove_filter %r{\A(test|features|spec|autotest)/}
  group         'Sources', 'lib'
  group         'Tests', 'spec'
  skip          'Vagrantfile*'
  root          VagrantPlugins::AnsibleAuto.source_root.to_s
  coverage_dir  VagrantPlugins::AnsibleAuto.source_root.join('coverage').to_s
end

if ENV.key? 'SIMPLECOV_VAGRANT_ANSIBLE_AUTO_COMMAND_NAME'
  SimpleCov.command_name ENV['SIMPLECOV_VAGRANT_ANSIBLE_AUTO_COMMAND_NAME']
  SimpleCov.formatter = SimpleCov::Formatter::SilentHTMLFormatter

  SimpleCov.start
else
  SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
end
