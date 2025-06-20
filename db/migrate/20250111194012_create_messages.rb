class CreateMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :messages do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.string :sender
      t.text :content
      t.string :role

      t.timestamps
    end
  end
end
