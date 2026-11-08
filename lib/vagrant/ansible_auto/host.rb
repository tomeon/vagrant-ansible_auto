# frozen_string_literal: true

require 'vagrant'

require 'vagrant/ansible_auto/util/hash_with_indifferent_access'
require 'vagrant/ansible_auto/util/keys'

module VagrantPlugins
  module AnsibleAuto
    # Class representing a single host in an Ansible inventory
    class Host
      include Util::Keys

      # @param [#to_s] name the name of the {Host} as it should appear in an
      #   {Inventory}
      # @param [Hash] hostvars variables to associate with the host
      def initialize(name, hostvars = {})
        @name = name

        # # Convert keys to symbols
        # @hostvars = hostvars.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
        self.hostvars = hostvars
      end

      # @return [String] the name of the {Host}, default +"default"+
      def name
        @name ||= 'default'
      end

      # @return [String] the name of the machine as a string
      def inventory_hostname
        @inventory_hostname ||= name.to_s
      end

      # @param new_name [#to_s] the name to associate with this host in the
      #   generated inventory
      # @return (see #inventory_hostname)
      def inventory_hostname=(new_name)
        @inventory_hostname = new_name.to_s
      end

      # @return [String] the SSH user for the {Host}, default +"vagrant"+
      def ansible_ssh_user
        hostvars[:ansible_ssh_user] ||= 'vagrant'
      end

      # @return [String] the hostname of the {Host}, default +"127.0.0.1"+
      def ansible_ssh_host
        hostvars[:ansible_ssh_host] ||= '127.0.0.1'
      end

      # @return [Integer] the SSH port of the {Host}, default +22+
      def ansible_ssh_port
        hostvars[:ansible_ssh_port] ||= 22
      end

      # The SSH private key file
      # @return [String] if the SSH private key file is defined
      # @return [nil] if no SSH private key file is defined
      def ansible_ssh_private_key_file
        hostvars[:ansible_ssh_private_key_file]
      end

      # The connection type
      # @return [String] if the connection type is defined
      # @return [nil] if no connection type is defined
      def ansible_connection
        hostvars[:ansible_connection]
      end

      # @return [Hash] the {Host}'s attributes keyed to its attribute names
      # @example
      #   host = Host.new("myhost", {ansible_ssh_user: 'me', ansible_ssh_port: 2200})
      #   host.hostvars #=> {
      #                 #     'ansible_ssh_user'  => 'me',
      #                 #     'ansible_ssh_host'  => '127.0.0.1',
      #                 #     'ansible_ssh_port'  => 2200,
      #                 #   }
      def hostvars
        @hostvars ||= Util::HashWithIndifferentAccess.new
      end

      # @param [Hash] hostvars the variables to set on the host
      # @return [Hash] the new hostvars
      def hostvars=(hostvars)
        raise ArgumentError, 'hostvars must be a hash' unless hostvars.is_a? Hash

        @hostvars = Util::HashWithIndifferentAccess.new(hostvars)
      end

      # @return [Hash{String=>Hash}] the {Host}'s {hostvars} keyed to its
      #   {name}
      def to_h
        finalize!
        { inventory_hostname => hostvars }
      end

      # @return [String] the {Host} represented as an entry in an Ansible
      #   INI-style static inventory
      # @example
      #   host = Host.new("myhost", {ssh_user: 'me', ssh_port: 2200})
      #   host.to_ini #=> "myhost ansible_ssh_user=me ansible_ssh_host=127.0.0.1 ansible_ssh_port=2200"
      def to_ini
        [inventory_hostname, *hostvars.sort.reject { |_, value| value.nil? }.map { |key, value| "#{key}=#{value}" }].join(' ')
      end

      # @return [Fixnum] hash key
      def hash
        to_h.hash
      end

      # @return [Boolean] whether two hosts are identical
      def eql?(other)
        to_h.eql?(other.to_h)
      end

    private

      def finalize!
        %i[ansible_connection ansible_ssh_user ansible_ssh_host ansible_ssh_port ansible_ssh_private_key_file].each do |m|
          send(m)
        end
      end

      def respond_to_missing?(method, _include_all = false)
        method.to_s.start_with? 'ansible_'
      end

      def method_missing(method, *args, &block)
        super unless respond_to_missing?(method)

        if method[-1] == '='
          hostvars[method[0..-2]] = args[0]
        else
          hostvars[method]
        end
      end
    end

    # An Ansible host initialized from a {Vagrant::Machine}
    class HostMachine < Host
      # @param [Vagrant::Machine] machine a {Vagrant::Machine} objectj
      # @param [Hash] hostvars  the hostvars associated with the machine
      def initialize(machine, hostvars = {})
        super(machine.name, hostvars)
        @machine = machine
      end

      # @see Host#ssh_user
      def ansible_ssh_user
        hostvars[:ansible_ssh_user] ||= ssh_info[:username] || super
      end

      # @see Host#ssh_host
      def ansible_ssh_host
        hostvars[:ansible_ssh_host] ||= ssh_info[:host] || super
      end

      # @see Host#ssh_port
      def ansible_ssh_port
        hostvars[:ansible_ssh_port] ||= ssh_info[:port] || super
      end

      # @see Host#ssh_private_key_file
      def ansible_ssh_private_key_file
        hostvars[:ansible_ssh_private_key_file] ||= fetch_private_key(@machine)
      end

    private

      def ssh_info
        @machine.ssh_info || {}
      end
    end
  end
end
