# frozen_string_literal: true

require 'optparse'

require 'vagrant/ansible_auto/errors'

module VagrantPlugins
  module AnsibleAuto
    # Vagrant +ansible+ subcommand
    module Command
      # Command for creating a static Ansible inventory from the machines
      # defined in a Vagrantfile
      class Root < Vagrant.plugin(2, :command)
        # @return [String] summary of the +ansible+ command
        def self.synopsis
          I18n.t('vagrant.ansible_auto.command.root.synopsis')
        end

        # Execute the +ansible+ command
        # @return [Integer] the exit status of the command
        def execute
          @argv, subcommand_name, subcommand_argv = split_main_and_subcommand(@argv)

          if subcommand_name.nil?
            @argv = ['-h'] if @argv.empty?
            parse_options(prepare_options)
          elsif subcommands.key? subcommand_name.to_sym
            subcommands.get(subcommand_name.to_sym).new(subcommand_argv, @env.dup).execute
          else
            raise Errors::UnrecognizedCommandError, command: subcommand_name
          end
        end

      private

        def prepare_options
          OptionParser.new do |op|
            op.banner = I18n.t('vagrant.ansible_auto.command.root.usage')
            op.separator ''
            op.separator I18n.t('vagrant.ansible_auto.command.root.available_subcommands')

            subcommands.keys.sort.each do |k|
              op.separator "    #{k}"
            end

            op.separator ''
            op.separator I18n.t('vagrant.ansible_auto.command.root.subcommand_help')
          end
        end

        def subcommands
          @subcommands ||= Vagrant::Registry.new.tap do |r|
            r.register(:inventory) do
              require_relative 'inventory'
              Inventory
            end
          end
        end
      end
    end
  end
end
