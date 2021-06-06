# frozen_string_literal: true

require 'vagrant/util/hash_with_indifferent_access'

module VagrantPlugins
  module AnsibleAuto
    # Helper methods for common operations
    module Util
      # Hash that automatically stringifies symbols or symbolifies strings if
      # lookups using the string or symbol fail.
      #
      # @example
      #
      #   ihash = HashWithIndifferentAccess.new { foo: 'bar' }
      #   ihash[:foo]
      #     #=> 'bar'
      #   ihash['foo']
      #     #=> 'bar'
      class HashWithIndifferentAccess < Vagrant::Util::HashWithIndifferentAccess
        # Combine two hashes into a new hash
        # @overload merge(other)
        #   @param (see #merge!)
        #   @return (see #merge!)
        # @overload merge(other, &block)
        #   @param (see #merge!)
        #   @return (see #merge!)
        #   @yieldparam (see #merge!)
        #   @yieldparam (see #merge!)
        #   @yieldparam (see #merge!)
        def merge(other, &block)
          dup.merge!(other, &block)
        end

        # In-place merge of two {HashWithIndifferentAccess} object.  Provide
        # the optional +&block+ argument if you want to control what happens a
        # key exists in both hashes; by default, the value from +other+
        # overwrites the current value for that key.
        # @overload merge!(other)
        #   @param [Hash] the hash to merge into the current hash
        #   @return [HashWithIndifferentAccess] the merged hash
        # @overload merge!(other, &block)
        #   @param [Hash] the hash to merge into the current hash
        #   @return [HashWithIndifferentAccess] the merged hash
        #   @yieldparam [String] key
        #   @yieldparam [HashWithIndifferentAccess] current
        #   @yieldparam [Hash] other
        def merge!(other)
          if block_given?
            other.each do |key, value|
              convert_key(key).tap do |ckey|
                self[ckey] = if key? ckey
                               yield(ckey, self[ckey], value)
                             else
                               value
                             end
              end
            end
          else
            super(other)
          end

          self
        end
      end
    end
  end
end
