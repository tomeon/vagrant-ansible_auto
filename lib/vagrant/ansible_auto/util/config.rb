# frozen_string_literal: true

require 'vagrant/util/deep_merge'

module VagrantPlugins
  module AnsibleAuto
    # Helper methods for common operations
    module Util
      # Helper module for operations related to configuration settings
      module Config
        # @return [Boolean] +false+ when an object is +nil+, undefined, or the
        #   special +UNSET_VALUE+ object, +true+ otherwise
        def unset?(o)
          o.nil? || !defined?(o) || (self.class.const_defined?(:UNSET_VALUE) && o == self.class.const_get(:UNSET_VALUE))
        end

        def bool?(o)
          (o == true) || (o == false)
        end

        def num?(o)
          float?(o) || int?(o)
        end

        def int?(o)
          coerced_int = int!(o)
          return false if coerced_int.nil?

          float!(coerced_int) == float!(o)
        end

        def int!(o)
          Integer(o)
        rescue ArgumentError, TypeError
          nil
        end

        def float?(o)
          !float!(o).nil?
        end

        def float!(o)
          Float(o)
        rescue ArgumentError, TypeError
          nil
        end

        # Deep merge two objects, ensuring first that neither object is
        # {#unset?}
        def conditional_merge(a, b, &block)
          if unset? b
            a
          elsif unset? a
            b
          else
            Vagrant::Util::DeepMerge.deep_merge(a, b, &block)
          end
        end
      end
    end
  end
end
