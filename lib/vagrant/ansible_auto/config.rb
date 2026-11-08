# frozen_string_literal: true

require 'vagrant'
require Vagrant.source_root + 'plugins/provisioners/ansible/config/guest'

require 'vagrant/ansible_auto/inventory'
require 'vagrant/ansible_auto/errors'
require 'vagrant/ansible_auto/util/config'

module VagrantPlugins
  module AnsibleAuto
    # Configuration for the +ansible_auto+ provisioner and +ansible+ command
    class Config < VagrantPlugins::Ansible::Config::Guest
      include Util::Config

      attr_accessor :inventory, :groups, :vars, :children,
                    :strict_host_key_checking, :host_connect_tries,
                    :host_connect_sleep, :insert_control_machine_public_key,
                    :upload_inventory_host_private_keys,
                    :include_inactive_machines

      protected(:inventory=)

      BOOLEAN = %I[
        strict_host_key_checking
        insert_control_machine_public_key
        upload_inventory_host_private_keys
      ].freeze

      INTEGER = %I[
        host_connect_tries
      ].freeze

      NUMBER = %I[
        host_connect_sleep
      ].freeze

      # Types permitted as elements of {#include_inactive_machines}
      MACHINE_PATTERN = [String, Symbol, Regexp].freeze

      def initialize
        super
        @inventory                          = Inventory.new
        @groups                             = UNSET_VALUE
        @vars                               = UNSET_VALUE
        @children                           = UNSET_VALUE
        @strict_host_key_checking           = UNSET_VALUE
        @host_connect_tries                 = UNSET_VALUE
        @host_connect_sleep                 = UNSET_VALUE
        @insert_control_machine_public_key  = UNSET_VALUE
        @upload_inventory_host_private_keys = UNSET_VALUE
        @include_inactive_machines          = UNSET_VALUE
        @__errors = []
      end

      # Set default configuration values at the end of constructing the Vagrant
      # environment
      # @api private
      # @return [void]
      def finalize!
        super
        @inventory.groups                   = @groups                             unless @groups                          == UNSET_VALUE
        @inventory.vars                     = @vars                               unless @vars                            == UNSET_VALUE
        @inventory.children                 = @children                           unless @children                        == UNSET_VALUE
        @strict_host_key_checking           = false                               if @strict_host_key_checking            == UNSET_VALUE
        @host_connect_tries                 = 10                                  if @host_connect_tries                  == UNSET_VALUE
        @host_connect_sleep                 = 2                                   if @host_connect_sleep                  == UNSET_VALUE
        @insert_control_machine_public_key  = true                                if @insert_control_machine_public_key   == UNSET_VALUE
        @upload_inventory_host_private_keys = !@insert_control_machine_public_key if @upload_inventory_host_private_keys  == UNSET_VALUE
        @include_inactive_machines          = false                               if @include_inactive_machines           == UNSET_VALUE
        @include_inactive_machines          = Array(@include_inactive_machines)   unless bool? @include_inactive_machines

        # NOTE: @limit is defined in core Vagrant's Ansible config.
        @limit = '*' if @limit == UNSET_VALUE
      rescue Errors::InventoryError => e
        @__errors << e.message
      end

      # Ensure that the configuration is in a valid state
      # @api private
      # @return [Hash{String=>Array}] a structure containing a list of errors
      #   under the +ansible_auto+ key
      def validate(machine)
        super

        errors = _detected_errors + @__errors

        BOOLEAN.each do |o|
          unless bool? instance_variable_get(:"@#{o}")
            errors << "#{o} must be either true or false"
          end
        end

        INTEGER.each do |o|
          unless int? instance_variable_get(:"@#{o}")
            errors << "#{o} must be an integer"
          end
        end

        NUMBER.each do |o|
          unless num? instance_variable_get(:"@#{o}")
            errors << "#{o} must be a number"
          end
        end

        unless machine_patterns? @include_inactive_machines
          errors << 'include_inactive_machines must be true, false, or a list of machine names and/or regular expressions'
        end

        { 'ansible_auto' => errors }
      end

      # Whether a machine that is not active (i.e. has not been created) should
      # be added to the inventory, as determined by
      # {#include_inactive_machines}.  +true+ selects all inactive machines,
      # +false+ selects none, and a list of names and/or regular expressions
      # selects the inactive machines whose names match any of its elements.
      # @param [#to_s] name the name of a machine
      # @return [Boolean] whether the machine should be added to the inventory
      def include_inactive_machine?(name)
        case include_inactive_machines
        when true
          true
        when Array
          include_inactive_machines.any? do |pattern|
            pattern.is_a?(Regexp) ? pattern.match?(name.to_s) : pattern.to_s == name.to_s
          end
        else
          false
        end
      end

      # Merge two configurations
      # @api private
      # @param [Config] other the configuration to merge into this
      #   configuration
      # @return [Config] the merged configuration
      def merge(other)
        return super if other.nil?

        super.tap do |result|
          result.groups     = conditional_merge(groups, other.groups)
          result.vars       = conditional_merge(vars, other.vars)
          result.children   = conditional_merge(children, other.children)
          result.inventory  = inventory.merge(other.inventory)
        end
      end

    private

      def machine_patterns?(o)
        bool?(o) || (o.is_a?(Array) && o.all? { |e| MACHINE_PATTERN.any? { |type| e.is_a? type } })
      end
    end
  end
end
