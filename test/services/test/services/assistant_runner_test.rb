require 'test_helper'
require 'ostruct'

class AssistantRunnerTest < ActiveSupport::TestCase
  class DummyMessages
    def initialize(list)
      @list = list
    end

    def where(conds)
      return self unless conds[:key]
      DummyMessages.new(@list.select { |m| m[:key] == conds[:key] })
    end

    def order(*)
      self
    end

    def last
      val = @list.last
      val && OpenStruct.new(val)
    end
  end

  def build_runner(messages)
    ra = OpenStruct.new(messages: DummyMessages.new(messages))
    runner = AssistantRunner.allocate
    runner.instance_variable_set(:@risk_assistant, ra)
    runner
  end

  test 'returns next missing field in arrays without count field' do
    child1 = { id: 'items.name', type: :string }
    child2 = { id: 'items.qty', type: :string }
    array  = { id: 'items', allow_add_remove_rows: true }

    RiskFieldSet.stub :by_id, {
      items: array,
      :'items.name' => child1,
      :'items.qty' => child2
    } do
      RiskFieldSet.stub :children_of_array, [child1, child2] do
        messages = [
          { key: 'items.0.name', value: 'a' },
          { key: 'items.0.qty',  value: '1' },
          { key: 'items.1.name', value: 'b' }
        ]
        runner = build_runner(messages)
        answered = messages.map { |m| m[:key] }.to_set
        result = runner.send(:next_from_array, 'items', [], answered)
        assert_equal :'items.1.qty', result
      end
    end
  end

  test 'asks for new row when allow_add_remove_rows is true' do
    child1 = { id: 'things.desc', type: :string }
    array  = { id: 'things', allow_add_remove_rows: true }

    RiskFieldSet.stub :by_id, { things: array, :'things.desc' => child1 } do
      RiskFieldSet.stub :children_of_array, [child1] do
        messages = [ { key: 'things.0.desc', value: 'one' } ]
        runner = build_runner(messages)
        answered = messages.map { |m| m[:key] }.to_set
        result = runner.send(:next_from_array, 'things', [], answered)
        assert_equal :'things.1.desc', result
      end
    end
  end

  test 'no extra rows requested when allow_add_remove_rows is false' do
    child1 = { id: 'recs.text', type: :string }
    array  = { id: 'recs', allow_add_remove_rows: false }

    RiskFieldSet.stub :by_id, { recs: array, :'recs.text' => child1 } do
      RiskFieldSet.stub :children_of_array, [child1] do
        messages = [ { key: 'recs.0.text', value: 'ok' } ]
        runner = build_runner(messages)
        answered = messages.map { |m| m[:key] }.to_set
        result = runner.send(:next_from_array, 'recs', [], answered)
        assert_nil result
      end
    end
  end
end