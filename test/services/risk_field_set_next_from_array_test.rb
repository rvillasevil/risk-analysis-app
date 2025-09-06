require 'test_helper'
require 'set'

class RiskFieldSetNextFromArrayTest < ActiveSupport::TestCase
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
        answered = Set.new(%w[items.0.name items.0.qty items.1.name])
        result = RiskFieldSet.send(:next_from_array, 'items', [], answered)
        assert_equal :'items.1.qty', result
      end
    end
  end

  test 'asks for new row when allow_add_remove_rows is true' do
    child1 = { id: 'things.desc', type: :string }
    array  = { id: 'things', allow_add_remove_rows: true }

    RiskFieldSet.stub :by_id, { things: array, :'things.desc' => child1 } do
      RiskFieldSet.stub :children_of_array, [child1] do
        answered = Set.new(%w[things.0.desc])
        result = RiskFieldSet.send(:next_from_array, 'things', [], answered)
        assert_equal :'things.1.desc', result
      end
    end
  end

  test 'no extra rows requested when allow_add_remove_rows is false' do
    child1 = { id: 'recs.text', type: :string }
    array  = { id: 'recs', allow_add_remove_rows: false }

    RiskFieldSet.stub :by_id, { recs: array, :'recs.text' => child1 } do
      RiskFieldSet.stub :children_of_array, [child1] do
        answered = Set.new(%w[recs.0.text])
        result = RiskFieldSet.send(:next_from_array, 'recs', [], answered)
        assert_nil result
      end
    end
  end
end