# frozen_string_literal: true

module VagrantPlugins
  module AnsibleAuto
    # Helper methods for common operations
    module Util
      # Helper methods for operations related to SSH keys
      module Keys
        # @return [Pathname] the path to the Vagrant insecure private key
        def insecure_key_path
          Vagrant.source_root.join('keys/vagrant')
        end

        # @return [String] the contents of the Vagrant insecure private key
        def insecure_key_contents
          @__insecure_key_contents ||= insecure_key_path.read.chomp # rubocop:disable Naming/MemoizedInstanceVariableName
        end

        # @param [String] path path to a file
        # @return [Boolean] whether the file is the Vagrant insecure private key
        # @note Adapted from
        #   {VagrantPlugins::CommunicatorSSH::Communicator#insecure_key?}
        def insecure_key?(path)
          return false if path.nil? || !File.file?(path)

          File.read(path).chomp == insecure_key_contents
        end

        # @param [Vagrant::Machine] machine a guest machine
        # @return [Array<String>] the first of the machine's keys that aren't the
        #   Vagrant private key as determined by {#insecure_key?}
        def fetch_private_key(machine)
          fetch_private_keys(machine).first
        end

        # @param (see #fetch_private_key)
        # @return [Array<String>] a list of the paths to all of the machine's
        #   keys that aren't the Vagrant private key as determined by
        #   {#insecure_key?}
        def fetch_private_keys(machine)
          if machine.config.ssh.insert_key && !machine.ssh_info.nil?
            machine.ssh_info.fetch(:private_key_path, []).find_all { |k| !insecure_key?(k) }
          else
            [machine.env.default_private_key_path]
          end
        end
      end
    end
  end
end
