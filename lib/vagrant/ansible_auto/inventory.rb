# frozen_string_literal: true

require 'set'
require 'json'

require 'vagrant/ansible_auto/errors'
require 'vagrant/ansible_auto/host'
require 'vagrant/ansible_auto/util/config'
require 'vagrant/ansible_auto/util/hash_with_indifferent_access'

module VagrantPlugins
  module AnsibleAuto
    # Class representing an Ansible inventory with hosts, groups, group
    # children, and group variables
    class Inventory
      include VagrantPlugins::AnsibleAuto::Util::Config

      UNNAMED_GROUP = '_'

      # @return [Hash{String=>Set<Host>}] group names mapped to their members
      def groups
        if unset? @groups
          @groups = Util::HashWithIndifferentAccess.new do |hash, key|
            hash[key] = Set.new
          end
        end

        @groups
      end

      # @return [Set<Host>] the hosts in the {Inventory}
      def hosts
        @hosts = Set.new if unset?(@hosts)
        @hosts
      end

      # @return [Hash{String=>Hash}] group names mapped to their variables
      def vars
        if unset? @vars
          @vars = Util::HashWithIndifferentAccess.new do |hash, key|
            hash[key] = Util::HashWithIndifferentAccess.new
          end
        end

        @vars
      end

      # @return [Hash{String=>Set}] group names mapped to their children
      def children
        if unset? @children
          @children = Util::HashWithIndifferentAccess.new do |hash, key|
            hash[key] = Set.new
          end
        end

        @children
      end

      # Set the groups for the {Inventory}.
      # @note overwrites the current {#groups}.
      # @param [Hash{String=>Array,Hash}] new_groups the groups to assign to the
      #   {Inventory}
      # @option new_groups [Array] group the hosts in +group+
      # @option new_groups [Hash] group:vars the variables for +group+
      # @option new_groups [Array] group:chilren the child groups for +group+
      # @return [Hash{String=>Array,Hash}] the created groups
      def groups=(new_groups)
        @groups = nil

        new_groups.each do |group_heading, entries|
          group, type = parse_group_heading(group_heading)

          case type
          when 'vars'
            entries = {} if entries.nil?
            vars_for(group, entries)
          when 'children'
            entries = [] if entries.nil?
            children_of(group, *entries)
          else
            entries = [] if entries.nil?
            if entries.is_a? Hash
              add_complex_group(group, entries)
            else
              add_group(group, *entries)
            end
          end
        end

        groups
      end

      # Set the hosts for the {Inventory}
      # @note overwrites the current {#hosts}.
      # @param [Hash{String=>Hash}] new_hosts the hosts in the inventory
      # @option new_hosts [Hash{String=>Hash, nil}] host a host plus any hostvars
      # @return [Hash{String=>Hash}] the created hosts
      def hosts=(new_hosts)
        @hosts = nil

        new_hosts.each do |host, hostvars|
          add_host(host, hostvars || {})
        end

        hosts
      end

      # Set the variables for the groups in the {Inventory}
      # @note overwrites the current {#vars}
      # @param [Hash{String,Hash}] new_vars the variables to add to the
      #   {Inventory}
      # @option new_vars [Hash{String,Hash}] group a group plus any group
      #   variables
      # @return [Hash{String,Hash}] the created variables
      def vars=(new_vars)
        @vars = nil

        new_vars.each do |group, group_vars|
          vars_for(group, group_vars)
        end

        vars
      end

      # Set the children of the groups in the {Inventory}
      # @note overwrites the currrent {#children}
      # @param [Hash{String=>Array<String>}] new_children the group children to add to
      #   the {Inventory}
      # @option new_children [Array<String>] group a group name and the list of
      #   its children
      # @return [Hash{String=>Set<String>}] the created children
      def children=(new_children)
        @children = nil

        new_children.each do |group, group_children|
          children_of(group, *group_children)
        end

        children
      end

      # Add a group to the {Inventory}
      # @param [#to_s] group the name of the group
      # @param [Array] members the hosts to add to the group
      # @return [Set] the members of the added group
      def add_group(group, *members)
        raise Errors::InvalidGroupNameError, group: group if group.to_s == UNNAMED_GROUP

        add_complex_group(group, members.pop) if members.last.is_a? Hash

        groups[group.to_s].tap do |group_members|
          group_members.merge(members)
          return group_members
        end
      end

      # Add a host to the {Inventory}
      # @param [Host,String,Symbol,Vagrant::Machine] host the host to add
      # @param [Hash] hostvars hostvars to assign to the host
      def add_host(host, hostvars = nil)
        hosts.add case host
                  when Host
                    host.tap { |h| h.hostvars = hostvars unless hostvars.nil? }
                  when String, Symbol
                    Host.new(host, hostvars || {})
                  when Vagrant::Machine
                    HostMachine.new(host, hostvars || {})
                  else
                    raise Errors::InvalidHostTypeError, type: host.class.name
                  end
      end

      # Assign variables to a group
      # @param [#to_s] group the name of the group
      # @param [Hash] new_vars the variables to assign to the group
      def vars_for(group, new_vars = {})
        vars[group.to_s].tap do |group_vars|
          group_vars.merge!(new_vars)
          return group_vars
        end
      end

      # Assign child groups to a group
      # @param [#to_s] group the name of the group
      # @param [Array] new_children the child groups to assign to the group
      def children_of(group, *new_children)
        children[group.to_s].tap do |group_children|
          group_children.merge(new_children.map(&:to_s))
          return group_children
        end
      end

      # Perform in-place merge of two {Inventory} instances
      # @param [Inventory] other the inventory to merge into this one
      # @return [self] the updated inventory
      def merge!(other)
        hosts.merge(other.hosts)

        @groups = groups.merge(other.groups) do |_group, group_members, other_group_members|
          group_members.merge(other_group_members)
        end

        @vars = vars.merge(other.vars) do |_group, group_vars, other_group_vars|
          group_vars.merge(other_group_vars)
        end

        @children = children.merge(other.children) do |_group, group_children, other_group_children|
          group_children.merge(other_group_children)
        end

        self
      end

      # Merge two {Inventory} instances
      # @param [Inventory] other the inventory to merge into this one
      # @return [Inventory] the updated inventory
      def merge(other)
        clone.merge!(other)
      end

      # @return [Hash{String=>Hash}] the merged hostvars for all hosts in the
      #   inventory
      def hostvars
        Hash[hosts.map { |h| [h.name, h.hostvars] }]
      end

      # A representation of an {Inventory} as a +Hash+
      # @note the hosts in the inventory will be returned as +Hash+es under the
      #   key {UNNAMED_GROUP}
      # @return [Hash{String=>Hash,Array}] a +Hash+ containing the hosts in the
      #   inventory (coerced to hashes) under the {UNNAMED_GROUP} key, as well
      #   as each group name mapped to a subhashes with hosts under the key
      #   +"hosts"+, variables under the key +"vars"+, and children under the
      #   key +"children"+
      def to_h
        Hash.new { |h, k| h[k] = {} }.tap do |h|
          h[UNNAMED_GROUP] = hosts.map(&:to_h)

          groups.each do |group, group_hosts|
            h[group]['hosts'] = group_hosts.to_a
          end

          vars.each do |group, group_vars|
            h[group]['vars'] = group_vars
          end

          children.each do |group, group_children|
            h[group]['children'] = group_children.to_a
          end
        end
      end

      # @return [String] the {Inventory} represented as a JSON object in the
      #   form of a "Dynamic Inventory"
      # @see http://docs.ansible.com/ansible/intro_dynamic_inventory.html
      def to_json(*args)
        to_h.tap do |h|
          h.delete(UNNAMED_GROUP)
          h['_meta'] = { 'hostvars' => hostvars }
        end.to_json(*args)
      end

      # Return the {Inventory} as an INI document
      # @return [String] the inventory in a newline-separated string
      def to_ini
        with_ini_lines.to_a.join("\n")
      end

      # Iterate over the lines of the {Inventory} represented as an INI
      # document
      # @overload
      #   @return [Enumerator] the lines of the INI document
      # @overload
      #   @yieldparam [String] each line in the INI document
      # @see with_ini_lines_hosts
      # @see with_ini_lines_groups
      def with_ini_lines
        return enum_for(__method__) unless block_given?

        [with_ini_lines_hosts, with_ini_lines_groups].each do |e|
          e.each { |line| yield line }
        end
      end

      # Iterate over the hosts in the {Inventory} represented as an INI
      # document
      # @overload
      #   @return [Enumerator] the lines of the INI document
      # @overload
      #   @yieldparam [String] each line in the INI document
      def with_ini_lines_hosts
        return enum_for(__method__) unless block_given?

        hosts.each { |host| yield host.to_ini }
      end

      # Iterate over the groups in the {Inventory} represented as an INI
      # document
      # @overload
      #   @return [Enumerator] the lines of the INI document
      # @overload
      #   @yieldparam [String] each line in the INI document
      def with_ini_lines_groups
        return enum_for(__method__) unless block_given?

        to_h.tap { |h| h.delete(UNNAMED_GROUP) }.sort.each do |group, entries|
          yield "[#{group}]"

          entries.fetch('hosts', []).sort.each { |h| yield h }

          if entries.key? 'children'
            yield "[#{group}:children]"
            entries['children'].sort.each { |c| yield c }
          end

          if entries.key? 'vars'
            yield "[#{group}:vars]"
            entries['vars'].sort.each { |k, v| yield "#{k} = #{v}" }
          end
        end
      end

      # A sanity check of the inventory's state
      # @return [void]
      # @raise [Errors::GroupMissingChildError] when a group has a child group
      #   that doesn't exist
      def validate!
        children.each do |group, group_children|
          group_children.each do |child|
            raise Errors::GroupMissingChildError, group: group, child: child unless groups.key? child
          end
        end
      end

    private

      def parse_group_heading(group_heading)
        group_elts = group_heading.to_s.split(/(?<!\\):/)
        type = group_elts.length > 1 && %w[vars children].include?(group_elts.last) ? group_elts.pop.chomp.strip : nil
        group = group_elts.join(':').chomp.strip
        [group, type]
      end

      def add_complex_group(group, group_spec = {})
        group_spec = Util::HashWithIndifferentAccess.new(group_spec)
        vars_for(group, group_spec['vars']) if group_spec.key? 'vars'
        children_of(group, *group_spec['children']) if group_spec.key? 'children'
        add_group(group, *group_spec['hosts']) if group_spec.key? 'hosts'
      end
    end
  end
end
