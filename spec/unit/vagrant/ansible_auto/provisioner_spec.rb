# frozen_string_literal: true

require 'spec_helper'

require 'log4r'

require 'vagrant/config/v2/dummy_config'

require 'vagrant/ansible_auto/provisioner'

describe VagrantPlugins::AnsibleAuto::Provisioner do
  include_context 'inventory'
  include_context 'config'

  def mock_capabilities(machine)
    capabilities = {
      ssh_server_address: ->(other) { [other.ssh_info[:host], other.ssh_info[:port]] },
      authorized_key?: ->(content, *args) { [true] },
      fetch_public_key: ->(path) {},
      insert_public_key: ->(key) { [] },
      ansible_installed: ->(*) { true }
    }

    allow(machine.guest).to receive(:capability?) { |cap| capabilities.key? cap }

    allow(machine.guest).to receive(:capability) do |cap, *args, &block|
      capabilities[cap].call(*args, &block) if capabilities.key? cap
    end
  end

  let(:provisioner) { described_class.new(machine, config) }
  let(:root_config) { Vagrant::Config::V2::DummyConfig.new }
  let(:existing_file) { File.expand_path(__FILE__) }
  let(:logger) { Log4r::Logger.new('vagrant::provisioners::ansible_auto::spec') }

  before do |example|
    unless example.metadata.fetch(:skip_before, false)
      # Allows us to set expectations on the provisioner's @logger instance
      # variable
      log4r_logger_new_original = Log4r::Logger.method(:new)
      allow(Log4r::Logger).to receive(:new) do |namespace, *args|
        if namespace == 'vagrant::provisioners::ansible_auto'
          logger
        else
          log4r_logger_new_original.call(namespace, *args)
        end
      end

      allow(root_config).to receive(:ansible).and_return(VagrantPlugins::AnsibleAuto::Config.new)

      config.playbook = existing_file
      config.finalize!
      root_config.finalize!
      machines.each do |m|
        m.config.ansible.finalize!
        mock_capabilities(m)
      end

      provisioner.configure(root_config)

      allow(machine.communicate).to receive(:execute) do |*args|
        0
      end

      allow(machine.communicate).to receive(:upload) do |*args|
        true
      end

      allow(machine.communicate).to receive(:test) do |*args|
        true
      end
    end
  end

  after do |example|
    provisioner.provision unless example.metadata.fetch(:skip_after, false)
  end

  describe '#provision' do
    it 'creates an ansible inventory', skip_after: true do
      expect(machine.communicate).to receive(:upload) do |from, to|
        contents = File.read(from)
        expect(contents).to match(/ansible_connection=local/)
      end
      expect { provisioner.provision }.not_to raise_error
      expect(provisioner.config.inventory).to be_a VagrantPlugins::AnsibleAuto::Inventory
    end

    context 'when strict host key checking' do
      let(:strict_host_key_checking_options) do
        "ansible_ssh_extra_args='-o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o StrictHostKeyChecking=no'"
      end

      context 'is enabled' do
        before do
          config.strict_host_key_checking = true
        end

        it 'omits StrictHostKeyChecking=yes and other SSH options from the inventory' do
          expect(machine.communicate).to receive(:upload) do |from, to|
            contents = File.read(from)
            expect(contents).not_to match(/#{strict_host_key_checking_options}/)
          end
        end
      end

      context 'is disabled' do
        before do
          config.strict_host_key_checking = false
        end

        it 'includes StrictHostKeyChecking=yes and other SSH options in the inventory' do
          expect(machine.communicate).to receive(:upload) do |from, to|
            contents = File.read(from)
            expect(contents).to match(/#{strict_host_key_checking_options}/)
          end
        end
      end
    end

    context 'when control machine public key insertion is enabled' do
      let(:public_key_content) { 'iamapublickey' }
      let(:private_key_content) { 'iamaprivatekey' }
      let(:openssh_content) { 'ssh iamsomebinarystuff vagrant' }

      before do
        config.insert_control_machine_public_key = true
        config.upload_inventory_host_private_keys = false
      end

      context 'and the control machine does not yet have a keypair configured' do
        before do
          allow(machine.communicate).to receive(:test).with(/^test -r/).and_return(false)
          allow(Vagrant::Util::Keypair).to receive(:create).and_return([nil, private_key_content, openssh_content])
        end

        it 'creates and uploads a new keypair' do
          expect(provisioner).to receive(:write_and_chown_and_chmod_remote_file).with(private_key_content, anything).and_call_original
          expect(provisioner).to receive(:write_and_chown_and_chmod_remote_file).with(openssh_content, anything).and_call_original
        end
      end

      context 'and the keypair is configured' do
        before do
          allow(provisioner).to receive(:control_machine_public_key).and_return(public_key_content)
        end

        context 'and the public key' do
          context 'is already authorized' do
            before do
              machines[1..-1].each do |m|
                allow(m.guest).to receive(:capability).with(:authorized_key?, public_key_content).and_return(true)
              end
            end

            it 'does not attempt to insert the public key' do
              machines[1..-1].each do |m|
                expect(m.guest).not_to receive(:capability).with(:insert_public_key, public_key_content)
              end
            end
          end

          context 'is not authorized' do
            before do
              machines[1..-1].each do |m|
                allow(m.guest).to receive(:capability).with(:authorized_key?, public_key_content).and_return(false)
              end
            end

            context 'and the other host permits public key insertion' do
              it 'attempts to insert the public key' do
                machines[1..-1].each do |m|
                  expect(m.guest).to receive(:capability).with(:insert_public_key, public_key_content)
                end
              end
            end

            context 'and the other host does not permit public key insertion' do
              it 'issues a warning' do
                machines[1..-1].each do |m|
                  allow(m.guest).to receive(:capability?).with(:insert_public_key).and_return(false)
                  expect(logger).to receive(:warn).with(/\ACannot insert control machine public key on/)
                end
              end
            end
          end
        end
      end
    end

    context 'when inventory host private key upload is enabled' do
      let(:private_key_content) { 'iamaprivatekey' }

      before do
        config.insert_control_machine_public_key = false
        config.upload_inventory_host_private_keys = true
      end

      context 'and the host has a private key configured' do
        it 'uploads the private key to the control machine' do
          machines[1..-1].each do |m|
            expect(provisioner).to receive(:fetch_private_key).with(m).and_return(private_key_content)
          end
        end
      end

      context 'and the host does not have a private key configured' do
        it 'issues a warning' do
          machines[1..-1].each do |m|
            allow(provisioner).to receive(:fetch_private_key).with(m).and_return(nil)
            expect(logger).to receive(:warn).with(/\APrivate key for .*? not available for upload; provisioner will likely fail/)
          end
        end
      end
    end

    context 'when both public key insertion and private key upload are disabled' do
      before do
        config.insert_control_machine_public_key = false
        config.upload_inventory_host_private_keys = false
      end

      it 'issues a warning message' do
        expect(machine.ui).to receive(:warn).with(/unable to insert public key or upload existing private key/).at_least(:once)
      end
    end

    context 'given a machine that is not ready for SSH' do
      before do
        config.host_connect_tries = 1
      end

      it 'errors out if a machine is not ready for SSH', skip_after: true do
        allow(machines[1].communicate).to receive(:ready?).and_return(false)
        expect { provisioner.provision }.to raise_error(Vagrant::Errors::SSHNotReady)
      end
    end

    context 'given machines that have not been created' do
      let(:vagrantfile_contents) do
        <<-VAGRANTFILE
          Vagrant.configure(2) do |config|
            config.vm.box = 'base'
            config.vm.define :machine1
            config.vm.define :machine2 do |m|
              m.vm.network :forwarded_port, guest: 80, host: 8080
              m.vm.network :private_network, ip: '192.168.56.12'
              m.vm.network :public_network, ip: '10.0.0.12'
              m.ssh.username = 'admin'
              m.ssh.guest_port = 2222
            end
            config.vm.define :machine3 do |m|
              m.vm.network :private_network, type: 'dhcp'
              m.vm.hostname = 'machine3.example.com'
            end
            config.vm.define :machine4
            config.vm.define :machine5
          end
        VAGRANTFILE
      end

      let(:active_machines) { [machines[0], machines[3]] }
      let(:inactive_machines) { [machines[1], machines[2], machines[4]] }

      def inventory_hostnames
        provisioner.config.inventory.hosts.map(&:inventory_hostname)
      end

      def inventory_host(name)
        provisioner.config.inventory.hosts.find { |h| h.inventory_hostname == name.to_s }
      end

      before do
        allow(machine.env).to receive(:active_machines).and_return(active_machines.map { |m| [m.name, :dummy] })
      end

      context 'by default' do
        it 'omits them from the inventory', skip_after: true do
          expect(machine.ui).not_to receive(:warn)
          provisioner.provision
          expect(inventory_hostnames).to eq %w[machine1 machine4]
        end
      end

      context 'when include_inactive_machines is true' do
        before do
          config.include_inactive_machines = true
        end

        it 'adds all of them to the inventory after the active machines', skip_after: true do
          provisioner.provision
          expect(inventory_hostnames).to eq %w[machine1 machine4 machine2 machine3 machine5]
        end

        it 'uses a static IP address, preferring public networks', skip_after: true do
          provisioner.provision
          expect(inventory_host(:machine2).hostvars).to include(
            'ansible_ssh_host' => '10.0.0.12',
            'ansible_ssh_port' => 2222,
            'ansible_ssh_user' => 'admin'
          )
          expect(inventory_host(:machine2).ansible_ssh_private_key_file).to be_nil
        end

        it 'falls back to the configured hostname', skip_after: true do
          provisioner.provision
          expect(inventory_host(:machine3).hostvars).to include(
            'ansible_ssh_host' => 'machine3.example.com',
            'ansible_ssh_port' => 22,
            'ansible_ssh_user' => 'vagrant'
          )
        end

        it 'falls back to the machine name', skip_after: true do
          provisioner.provision
          expect(inventory_host(:machine5).hostvars).to include('ansible_ssh_host' => 'machine5')
        end

        it 'writes them to the generated inventory' do
          expect(machine.communicate).to receive(:upload) do |from, to|
            contents = File.read(from)
            expect(contents).to match(/^machine2 .*ansible_ssh_host=10\.0\.0\.12 ansible_ssh_port=2222 ansible_ssh_user=admin/)
            expect(contents).to match(/^machine3 .*ansible_ssh_host=machine3\.example\.com/)
          end
        end

        it 'does not wait for them to become reachable or configure SSH access to them' do
          allow(provisioner).to receive(:wait_for_ssh_ready!).and_call_original
          allow(provisioner).to receive(:configure_ssh_access!).and_call_original

          inactive_machines.each do |m|
            expect(provisioner).not_to receive(:wait_for_ssh_ready!).with(m, any_args)
            expect(provisioner).not_to receive(:configure_ssh_access!).with(m, any_args)
          end

          expect(provisioner).to receive(:wait_for_ssh_ready!).with(machines[3], any_args)
        end

        it 'includes groups and variables from their configuration', skip_after: true do
          machines[1].config.ansible.groups = { 'workers' => %w[machine2] }
          machines[1].config.ansible.vars = { 'workers' => { 'role' => 'worker' } }
          machines[1].config.ansible.finalize!

          provisioner.provision

          expect(provisioner.config.inventory.groups['workers']).to include('machine2')
          expect(provisioner.config.inventory.vars['workers']).to include('role' => 'worker')
        end
      end

      context 'when include_inactive_machines lists machine names' do
        before do
          config.include_inactive_machines = ['machine2', :machine5, 'machine4']
        end

        it 'adds only the listed machines to the inventory', skip_after: true do
          provisioner.provision
          expect(inventory_hostnames).to eq %w[machine1 machine4 machine2 machine5]
        end
      end

      context 'when include_inactive_machines lists regular expressions' do
        before do
          config.include_inactive_machines = [/[35]\z/]
        end

        it 'adds only the matching machines to the inventory', skip_after: true do
          provisioner.provision
          expect(inventory_hostnames).to eq %w[machine1 machine4 machine3 machine5]
        end
      end

      context 'when include_inactive_machines lists a machine that is not defined' do
        before do
          config.include_inactive_machines = %w[machine2 nonexistent]
        end

        it 'issues a warning' do
          expect(machine.ui).to receive(:warn).with(/\AMachine nonexistent is listed in include_inactive_machines but is not defined/)
        end
      end
    end

    context 'given a machine that is not configured for the current environment' do
      it 'carps and ignores the machine', skip_after: true do
        expect(logger).to receive(:warn).with(/\AMachine .*? not configured for this environment/).at_least(:once)
        expect(logger).to receive(:warn).with(/\AUnable to find machine/).at_least(:once)
        allow(machine.env).to receive(:machine).and_raise(Vagrant::Errors::MachineNotFound, name: 'dummy')
        provisioner.provision
      end
    end
  end
end
