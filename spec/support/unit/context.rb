# frozen_string_literal: true

require 'vagrant'
require Vagrant.source_root.join('test/unit/support/dummy_communicator')
require 'vagrant-spec/unit'

def unindent(s)
  s.lines.tap do |lines|
    indent = lines.map { |l| l.length - l.lstrip.length }.min
    return lines.map { |l| l[indent..-1] }.join
  end
end

shared_context 'machine' do |machine_count = 2|
  include_context 'vagrant-unit'

  def mock_communicator(machine)
    VagrantTests::DummyCommunicator::Communicator.new(machine)
  end

  def mock_guest
    double('guest')
  end

  def mock_machine_state
    double('state').tap do |s|
      allow(s).to receive(:id).and_return(:running)
    end
  end

  def mock_ssh_info
    {}.tap do |i|
      allow(i).to receive(:[])
      allow(i).to receive(:fetch).with(:private_key_path, anything).and_return([])
    end
  end

  def mock_ui
    Vagrant::UI::Colored.new
  end

  def mock_machine(name)
    iso_env.machine(name, :dummy).tap do |m|
      allow(m).to receive(:state).and_return(mock_machine_state)
      allow(m).to receive(:ssh_info).and_return(mock_ssh_info)
      allow(m).to receive(:ui).and_return(mock_ui)
      allow(m).to receive(:communicate).and_return(mock_communicator(m))
      allow(m).to receive(:guest).and_return(mock_guest)
      allow(m.env).to receive(:active_machines).and_return(iso_env.machine_names.map { |n| [n, :dummy] })
    end
  end

  let(:vagrantfile_contents) do
    <<-VAGRANTFILE
      Vagrant.configure(2) do |config|
        config.vm.box = 'base'
        #{(1..machine_count).map { |c| "config.vm.define :machine#{c}" }.join("\n")}
      end
    VAGRANTFILE
  end

  # Lifted from core Ansible provisioner tests
  let(:iso_env) do
    env = isolated_environment
    env.vagrantfile(vagrantfile_contents)
    env.create_vagrant_env
  end

  let(:machines) { iso_env.machine_names.map { |n| mock_machine(n) } }
  let(:machine) { machines[0] }
  let(:machine_name) { machine.name }
  let(:state) { machine.state }
  let(:ssh_info) { machine.ssh_info }
  let(:ui) { machine.ui }
  let(:communicator) { machine.communicator }
  let(:playbook) { 'playbook.yml' }

  before do |example|
    # Ensure that we always create the Vagrant::Environment, unless explicitly
    # told not to
    iso_env unless example.metadata.fetch(:skip_create_vagrant_env, false)
  end
end

shared_context 'host' do
  require 'vagrant/ansible_auto/host'

  include_context 'machine'

  let(:hostvars) { {} }
  let(:inventory_hostname) { machine_name.to_s }
  let(:host) { VagrantPlugins::AnsibleAuto::Host.new(machine_name, hostvars) }
  let(:host_machine) { VagrantPlugins::AnsibleAuto::HostMachine.new(machine, hostvars) }
end

shared_context 'inventory' do
  require 'vagrant/ansible_auto/inventory'

  include_context 'machine'

  let(:inventory) { VagrantPlugins::AnsibleAuto::Inventory.new }
end

shared_context 'config' do
  require 'vagrant/ansible_auto/config'

  include_context 'machine'
  include_context 'inventory'

  let(:config) { VagrantPlugins::AnsibleAuto::Config.new }

  before do
    allow(config).to receive(:inventory).and_return(inventory)

    machines.each do |m|
      allow(m.config).to receive(:ansible).and_return(VagrantPlugins::AnsibleAuto::Config.new)
    end
  end
end
