class CreateAlmacenamientos < ActiveRecord::Migration[7.0]
  def change
    create_table :almacenamientos do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.text :materias_primas
      t.decimal :carga_fuego
      t.string :tipo_almacenamiento
      t.decimal :altura_almacenamiento
      t.boolean :congestion
      t.boolean :productos_combustibles
      t.boolean :estabilidad_almacenamiento

      t.timestamps
    end
  end
end
