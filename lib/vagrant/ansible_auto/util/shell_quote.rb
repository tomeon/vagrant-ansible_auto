# frozen_string_literal: true

module VagrantPlugins
  module AnsibleAuto
    # Helper methods for common operations
    module Util
      # Helper methods for operations related to SSH keys
      module ShellQuote
        # In-place equivalent of {#shellescape}
        # @param text [#to_s] the text to escape
        # @return [String] the text, with all occurrences of +'+ replaced by
        #   +'"'"'+
        def shellescape!(text)
          text.to_s.gsub!(%('), %('"'"'))
        end

        # Escape a string for use as a shell parameter
        # @param (see #shellescape!)
        # @return (see #shellescape!)
        def shellescape(text)
          text.to_s.gsub(%('), %('"'"'))
        end
      end
    end
  end
end
