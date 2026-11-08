# frozen_string_literal: true

# vagrant-spec's Subprocess.execute forwards only positional arguments, so on
# Ruby 3 the keyword options (notably :notify) are dropped and every command
# fails with "A list of notify subscriptions must be given if a block is
# given".  Forward the keywords explicitly until this is fixed upstream.
Vagrant::Spec::Subprocess.singleton_class.prepend(Module.new do
  def execute(command, *args, **options, &block)
    new(command, *args, **options).execute(&block)
  end
end)

Vagrant::Spec::Acceptance.configure do |config|
  config.component_paths << 'spec/acceptance'
  config.skeleton_paths << 'spec/acceptance/support-skeletons'

  # Silence Vagrant's "You appear to be running Vagrant outside of the official
  # installers" message.  This message mucks up things like parsing the output
  # of `vagrant-skel` with JSON.load.  Also disable the bit that checks whether
  # a newer version of Vagrant is available, as it also breaks JSON.load.
  config.env.merge!(
    'VAGRANT_I_KNOW_WHAT_IM_DOING_PLEASE_BE_QUIET'  => '1',
    'VAGRANT_CHECKPOINT_DISABLE'                    => '1'
  )
end

# Pull in SimpleCov and RSpec setup
require_relative 'spec/spec_helper'
