# frozen_string_literal: true

require 'vagrant'
require Vagrant.source_root + 'plugins/provisioners/ansible/provisioner/guest'
require 'vagrant/util/keypair'

require 'vagrant/ansible_auto/util/keys'

require 'i18n'
require 'log4r'

module VagrantPlugins
  module AnsibleAuto
    # Class backing the +ansible_auto+ provisioner
    class Provisioner < VagrantPlugins::Ansible::Provisioner::Guest
      include Vagrant::Util::Retryable
      include Util::Keys

      def initialize(machine, config)
        super
        @logger = Log4r::Logger.new('vagrant::provisioners::ansible_auto')
      end

      # Configure the provisioner by storing the root Ansible configuration
      # object for use as the set of base options for a particular machine
      # @api private
      # @return [void]
      def configure(root_config)
        super
        @__ansible_config = root_config.ansible
      end

      # Provision a {Vagrant::Machine} with the +ansible_auto+ provisioner
      # @api private
      # @return [void]
      def provision
        @config = @__ansible_config.merge(config)

        return super unless machine.guest.capability?(:ssh_server_address)

        with_active_machines do |other, name, provider|
          if other.nil?
            @logger.warn I18n.t('vagrant.ansible_auto.provisioner.machine_not_configured', machine_name: name)
          else
            if name == machine.name
              other_hostvars = { ansible_connection: 'local' }
            else
              # Merge the other machine's configuration, with this machine's
              # configuration taking precedence.
              @config = other.config.ansible.merge(@config)

              wait_for_ssh_ready!(other, @config.host_connect_tries, @config.host_connect_sleep)

              ssh_host, ssh_port = machine.guest.capability(:ssh_server_address, other)
              other_hostvars = { ansible_ssh_host: ssh_host, ansible_ssh_port: ssh_port }

              machine.ui.info I18n.t('vagrant.ansible_auto.provisioner.inventory_addition', machine_name: name)

              unless (other_ssh_private_key_file = configure_ssh_access!(other, name, provider)).nil?
                other_hostvars[:ansible_ssh_private_key_file] = other_ssh_private_key_file
              end
            end

            @config.inventory.add_host(other, other_hostvars || {})
          end
        end

        @config.inventory.validate!

        super
      end

    private

      def control_machine_ssh_key_dir
        Pathname.new(@config.tmp_path).join('ssh')
      end

      def control_machine_private_key_path
        @control_machine_private_key_path ||= control_machine_ssh_key_dir.join('vagrant_ansible_id_rsa')
      end

      def control_machine_public_key_path
        @control_machine_public_key_path ||= control_machine_private_key_path.sub_ext('.pub')
      end

      def control_machine_public_key
        @control_machine_public_key ||= configure_keypair!
      end

      def configure_ssh_access!(other, name, provider)
        # Insert the control machine's public key on the target machines
        if config.insert_control_machine_public_key
          insert_control_machine_public_key!(other, name)
        elsif config.upload_inventory_host_private_keys
          upload_inventory_host_private_key!(other, name, provider)
        else
          machine.ui.warn I18n.t('vagrant.ansible_auto.provisioner.cannot_configure_keys', machine_name: name)
        end
      end

      def insert_control_machine_public_key!(other, name)
        # Don't bother inserting the key if it is already authorized
        if other.guest.capability?(:authorized_key?) && other.guest.capability(:authorized_key?, control_machine_public_key)
          @logger.info I18n.t('vagrant.ansible_auto.provisioner.public_key_authorized', machine_name: name)
        elsif other.guest.capability?(:insert_public_key)
          @logger.info I18n.t('vagrant.ansible_auto.provisioner.inserting_public_key', machine_name: name)
          other.guest.capability(:insert_public_key, control_machine_public_key)
        else
          @logger.warn I18n.t('vagrant.ansible_auto.provisioner.cannot_insert_public_key', machine_name: name)
          return
        end

        control_machine_private_key_path
      end

      def upload_inventory_host_private_key!(other, name, provider)
        source_priv_key_path = fetch_private_key(other)

        if source_priv_key_path.nil?
          @logger.warn I18n.t('vagrant.ansible_auto.provisioner.private_key_missing', machine_name: name)
          return
        end

        @logger.info I18n.t('vagrant.ansible_auto.provisioner.uploading_private_key', machine_name: name)

        other_priv_key_path = control_machine_ssh_key_dir.join(name.to_s, provider.to_s, File.basename(source_priv_key_path))
        create_and_chown_and_chmod_remote_file(source_priv_key_path, other_priv_key_path)
        other_priv_key_path
      end

      def configure_keypair!
        # Check whether user already has a private key
        if !machine.communicate.test("test -r #{control_machine_private_key_path} && test -r #{control_machine_public_key_path}")
          _pub, priv, openssh = Vagrant::Util::Keypair.create
          write_and_chown_and_chmod_remote_file(priv, control_machine_private_key_path)
          write_and_chown_and_chmod_remote_file(openssh, control_machine_public_key_path)
        elsif machine.guest.capability?(:fetch_public_key)
          openssh = machine.guest.capability(:fetch_public_key, control_machine_private_key_path)
        end

        openssh
      end

      def handle_remote_file(to, opts = {})
        owner = opts.fetch(:owner) { machine.ssh_info[:username] }
        mode = opts.fetch(:mode) { 0o600 }
        machine.communicate.tap do |comm|
          # NOTE create_and_chown_remote_folder is defined in the parent class
          create_and_chown_remote_folder(File.dirname(to))

          yield comm, to

          comm.sudo("chown -h #{owner} #{to}")
          comm.sudo("chmod #{format('0%o', mode)} #{to}")
        end
      end

      # This method used to be defined on
      # VagrantPlugins::Ansible::Provisioner::Guest, but was removed:
      # @see https://github.com/hashicorp/vagrant/commit/0d23724a1fcf87e1ab86be85e15516eca9e32e8d
      def create_and_chown_remote_folder(path)
        machine.communicate.tap do |comm|
          comm.sudo("mkdir -p #{path}")
          comm.sudo("chown -R -h #{machine.ssh_info[:username]} #{path}")
        end
      end

      def create_and_chown_and_chmod_remote_file(from, to, opts = {})
        handle_remote_file(to, opts) do |comm, target|
          comm.upload(from, target)
        end
      end

      def write_and_chown_and_chmod_remote_file(contents, to, opts = {})
        handle_remote_file(to, opts) do |comm, target|
          contents = contents.strip << "\n"

          remote_path = "/tmp/vagrant-temp-asset-#{Time.now.to_i}"
          Tempfile.open('vagrant-temp-asset') do |f|
            f.binmode
            f.write(contents)
            f.fsync
            f.close
            machine.ui.detail I18n.t('vagrant.ansible_auto.provisioner.uploading_file', local_path: f.path, remote_path: remote_path)
            comm.upload(f.path, remote_path)
          end

          # Parent directory of target will already exist
          comm.execute("mv #{remote_path} #{target}")
        end
      end

      def generate_inventory_machines
        machine_format = if config.strict_host_key_checking
                           '%s'
                         else
                           "%s ansible_ssh_extra_args='-o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o StrictHostKeyChecking=no'"
                         end

        config.inventory.with_ini_lines_hosts.map do |host_spec|
          machine_format % host_spec
        end.join("\n") + "\n"
      end

      def generate_inventory_groups
        config.inventory.with_ini_lines_groups.to_a.join("\n") + "\n"
      end

      def with_active_machines
        return enum_for(__method__) unless block_given?

        machine.env.active_machines.each do |name, provider|
          begin
            yield machine.env.machine(name, provider), name, provider
          rescue Vagrant::Errors::MachineNotFound, CommunicatorWinRM::Errors::WinRMNotReady => e
            @logger.warn I18n.t('vagrant.ansible_auto.provisioner.cannot_find_machine', machine_name: name, error_message: e.message)
            yield nil, name, provider
          end
        end
      end

      # The machines we are trying to manage might not yet be ready to
      # connect -- retry a configurable number of times/durations until
      # we can connect; otherwise raise an exception.
      def wait_for_ssh_ready!(other, tries, sleep)
        retryable(on: Vagrant::Errors::SSHNotReady, tries: tries, sleep: sleep) do
          raise Vagrant::Errors::SSHNotReady unless other.communicate.ready? && !other.ssh_info.nil?
        end
      end
    end
  end
end
