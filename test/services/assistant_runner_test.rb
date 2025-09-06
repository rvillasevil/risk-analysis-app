require 'test_helper'

class AssistantRunnerTest < ActiveSupport::TestCase
  setup do
    @risk_assistant = risk_assistants(:one)
    @risk_assistant.messages.delete_all
  end

  def build_runner
    r = AssistantRunner.allocate
    r.instance_variable_set(:@risk_assistant, @risk_assistant)
    r
  end

  test 'returns fields following JSON order including arrays' do
    fields = [
      { id: 'first', type: :string, parent: nil },
      { id: 'arr', type: :array_of_objects, parent: nil },
      { id: 'arr.name', type: :string, parent: 'arr' },
      { id: 'arr.subarr', type: :array_of_objects, parent: 'arr' },
      { id: 'arr.subarr.attr', type: :string, parent: 'arr.subarr' },
      { id: 'second', type: :string, parent: nil }
    ]

    by_id = fields.index_by { |f| f[:id].to_sym }

    RiskFieldSet.stub :flat_fields, fields do
      RiskFieldSet.stub :by_id, by_id do
        RiskFieldSet.stub :children_of_array, ->(id) { fields.select { |f| f[:parent] == id } } do
          runner = build_runner

          assert_equal :first, runner.next_pending_field

          @risk_assistant.messages.create!(sender: 'assistant', role: 'assistant', key: 'first', value: 'v', content: 'c')
          assert_equal :'arr.0.name', runner.next_pending_field

          @risk_assistant.messages.create!(sender: 'assistant', role: 'assistant', key: 'arr.0.name', value: 'v', content: 'c')
          assert_equal :'arr.0.subarr.0.attr', runner.next_pending_field

          @risk_assistant.messages.create!(sender: 'assistant', role: 'assistant', key: 'arr.0.subarr.0.attr', value: 'v', content: 'c')
          assert_equal :second, runner.next_pending_field
        end
      end
    end
  end
end
