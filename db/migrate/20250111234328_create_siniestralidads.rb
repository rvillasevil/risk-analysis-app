class CreateSiniestralidads < ActiveRecord::Migration[7.0]
  def change
    create_table :siniestralidads do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.date :fecha
      t.text :causa
      t.decimal :costo
      t.text :medidas_adoptadas

      t.timestamps
    end
  end
end
