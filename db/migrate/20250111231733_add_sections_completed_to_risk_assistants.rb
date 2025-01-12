class AddSectionsCompletedToRiskAssistants < ActiveRecord::Migration[7.0]
  def change
    add_column :risk_assistants, :sections_completed, :jsonb
  end
end
