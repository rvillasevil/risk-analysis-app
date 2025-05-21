class AddInitialisedToRiskAssistants < ActiveRecord::Migration[7.0]
  def change
    add_column :risk_assistants, :initialised, :boolean, default: false, null: false
  end
end
