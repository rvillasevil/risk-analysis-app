class AddThreadIdToRiskAssistants < ActiveRecord::Migration[7.0]
  def change
    add_column :risk_assistants, :thread_id, :string
  end
end
