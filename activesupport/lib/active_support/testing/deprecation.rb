# frozen_string_literal: true

require "active_support/deprecation"

module ActiveSupport
  module Testing
    module Deprecation
      ##
      # :call-seq:
      #   assert_deprecated(&block)
      #   assert_deprecated(match, &block)
      #   assert_deprecated(deprecator, &block)
      #   assert_deprecated(match, deprecator, &block)
      #
      # Asserts that a matching deprecation warning was emitted by the given deprecator during the execution of the yielded block.
      #
      #   assert_deprecated(/foo/, CustomDeprecator) do
      #     CustomDeprecator.warn "foo should no longer be used"
      #   end
      #
      # The +match+ object may be a +Regexp+, or +String+ appearing in the message.
      #
      #   assert_deprecated('foo', CustomDeprecator) do
      #     CustomDeprecator.warn "foo should no longer be used"
      #   end
      #
      # If the +match+ is omitted (or explicitly +nil+), any deprecation warning will match.
      #
      #   assert_deprecated(CustomDeprecator) do
      #     CustomDeprecator.warn "foo should no longer be used"
      #   end
      #
      # If no +deprecator+ is given, defaults to ActiveSupport::Deprecation.
      #
      #   assert_deprecated do
      #     ActiveSupport::Deprecation.warn "foo should no longer be used"
      #   end
      def assert_deprecated(match = nil, deprecator = nil, &block)
        match, deprecator = nil, match if match.is_a?(ActiveSupport::Deprecation)
        result, warnings = collect_deprecations(deprecator, &block)
        assert !warnings.empty?, "Expected a deprecation warning within the block but received none"
        if match
          match = Regexp.new(Regexp.escape(match)) unless match.is_a?(Regexp)
          assert warnings.any? { |w| match.match?(w) }, "No deprecation warning matched #{match}: #{warnings.join(', ')}"
        end
        result
      end

      # Asserts that no deprecation warnings are emitted by the given deprecator during the execution of the yielded block.
      #
      #   assert_not_deprecated(CustomDeprecator) do
      #     CustomDeprecator.warn "message" # fails assertion
      #   end
      #
      # If no +deprecator+ is given, defaults to ActiveSupport::Deprecation.
      #
      #   assert_not_deprecated do
      #     ActiveSupport::Deprecation.warn "message" # fails assertion
      #   end
      #
      #   assert_not_deprecated do
      #     CustomDeprecator.warn "message" # passes assertion
      #   end
      def assert_not_deprecated(deprecator = nil, &block)
        result, deprecations = collect_deprecations(deprecator, &block)
        assert deprecations.empty?, "Expected no deprecation warning within the block but received #{deprecations.size}: \n  #{deprecations * "\n  "}"
        result
      end

      # Returns the return value of the block and an array of all the deprecation warnings emitted by the given
      # +deprecator+ during the execution of the yielded block.
      #
      #   collect_deprecations(CustomDeprecator) do
      #     CustomDeprecator.warn "message"
      #     :result
      #   end # => [:result, ["message"]]
      #
      # If no +deprecator+ is given, defaults to ActiveSupport::Deprecation.
      #
      #   collect_deprecations do
      #     CustomDeprecator.warn "custom message"
      #     ActiveSupport::Deprecation.warn "message"
      #     :result
      #   end # => [:result, ["message"]]
      def collect_deprecations(deprecator = nil)
        deprecator ||= ActiveSupport::Deprecation
        old_behavior = deprecator.behavior
        deprecations = []
        deprecator.behavior = Proc.new do |message, callstack|
          deprecations << message
        end
        result = yield
        [result, deprecations]
      ensure
        deprecator.behavior = old_behavior
      end
    end
  end
end
