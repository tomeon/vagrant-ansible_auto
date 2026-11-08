# frozen_string_literal: true

require 'spec_helper'

require 'vagrant/ansible_auto/config'

describe VagrantPlugins::AnsibleAuto::Config do
  include_context 'config'

  let(:include_inactive_machines_error) do
    'include_inactive_machines must be true, false, or a list of machine names and/or regular expressions'
  end

  def validate_config(c, m, attr, v)
    c.public_send("#{attr}=", v)
    c.finalize!
    errors = c.validate(m)
    yield errors['ansible_auto']
  end

  describe '#validate' do
    context 'given an invalid value for a configuration parameter' do
      it 'catches the error and returns it under the "ansible_auto" key' do
        described_class::BOOLEAN.each do |attr|
          validate_config(config, machine, attr, 5) do |errors|
            expect(errors).to include("#{attr} must be either true or false")
          end
        end

        described_class::INTEGER.each do |attr|
          validate_config(config, machine, attr, nil) do |errors|
            expect(errors).to include("#{attr} must be an integer")
          end
        end

        described_class::NUMBER.each do |attr|
          validate_config(config, machine, attr, nil) do |errors|
            expect(errors).to include("#{attr} must be a number")
          end
        end

        [5, { 'machine1' => true }, ['machine1', 5]].each do |value|
          validate_config(config, machine, :include_inactive_machines, value) do |errors|
            expect(errors).to include(include_inactive_machines_error), "expected an error for #{value.inspect}"
          end
        end
      end
    end

    context 'given an error constructing the inventory' do
      it 'catches the error and returns it under the "ansible_auto" key' do
        pending 'at the moment, the inventory object does not raise any errors along the relevant code paths'
        config.finalize!
        errors = config.validate(machine)
        expect(errors['ansible_auto']).not_to be_empty
      end
    end

    context 'given a valid value for a configuration parameter' do
      it 'does not catch the error and return it under the "ansible_auto" key' do
        described_class::BOOLEAN.each do |attr|
          validate_config(config, machine, attr, true) do |errors|
            expect(errors).not_to include("#{attr} must be either true or false")
          end
        end

        described_class::INTEGER.each do |attr|
          validate_config(config, machine, attr, 10) do |errors|
            expect(errors).not_to include("#{attr} must be an integer")
          end
        end

        described_class::NUMBER.each do |attr|
          validate_config(config, machine, attr, 3.14159) do |errors|
            expect(errors).not_to include("#{attr} must be a number")
          end
        end

        [true, false, [], 'machine1', :machine1, /machine/, ['machine1', :machine2, /machine/]].each do |value|
          validate_config(config, machine, :include_inactive_machines, value) do |errors|
            expect(errors).not_to include(include_inactive_machines_error), "expected no error for #{value.inspect}"
          end
        end
      end
    end
  end

  describe '#include_inactive_machines' do
    it 'defaults to false' do
      config.finalize!
      expect(config.include_inactive_machines).to be false
    end

    it 'wraps a single machine name or pattern in a list' do
      ['machine1', :machine1, /machine/].each do |value|
        config.include_inactive_machines = value
        config.finalize!
        expect(config.include_inactive_machines).to eq [value]
      end
    end
  end

  describe '#include_inactive_machine?' do
    names = %i[machine1 machine2 other]

    {
      false                     => [],
      true                      => %i[machine1 machine2 other],
      []                        => [],
      ['machine1', :machine2]   => %i[machine1 machine2],
      [/\Amachine/]             => %i[machine1 machine2],
      ['other', /2\z/]          => %i[machine2 other],
      ['nonexistent']           => []
    }.each do |value, expected|
      context "given #{value.inspect}" do
        it "selects #{expected.inspect}" do
          config.include_inactive_machines = value
          config.finalize!
          expect(names.select { |n| config.include_inactive_machine?(n) }).to eq expected
          expect(names.select { |n| config.include_inactive_machine?(n.to_s) }).to eq expected
        end
      end
    end
  end
end
