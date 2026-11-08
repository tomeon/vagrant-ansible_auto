# frozen_string_literal: true

require 'rspec'

# We're using an older version of rspec-expectations that doesn't have the
# `all' matcher.
RSpec::Matchers.define :all do |expected|
  define_method :index_failed_objects do |actual|
  end

  def index_failed_objects(actual)
    return enum_for(__method__, actual) unless block_given?

    @failed_items = []

    actual.each_with_index do |o, i|
      @failed_items[i] = yield o
    end

    @failed_items.compact.empty?
  end

  match_for_should do |actual|
    index_failed_objects(actual) do |item|
      expected.failure_message_for_should unless expected.matches?(item)
    end
  end

  match_for_should_not do |actual|
    index_failed_objects(actual) do |item|
      expected.failure_message_for_should_not if expected.matches?(item)
    end
  end

  def failure_message(actual)
    if actual.respond_to?(:each_with_index)
      @failed_items.each_with_index.reject { |f, _i| f.nil? }.map do |f, i|
        "object at index #{i} failed to match: #{f}"
      end.join("\n")
    else
      'provided object is not iterable'
    end
  end

  failure_message_for_should      { |actual| failure_message(actual) }
  failure_message_for_should_not  { |actual| failure_message(actual) }
end
