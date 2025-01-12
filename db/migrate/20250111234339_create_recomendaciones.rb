class CreateRecomendaciones < ActiveRecord::Migration[7.0]
  def change
    create_table :recomendaciones do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.text :accion
      t.string :estado
      t.string :prioridad

      t.timestamps
    end
  end
end
