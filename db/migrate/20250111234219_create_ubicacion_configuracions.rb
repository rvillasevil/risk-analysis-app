class CreateUbicacionConfiguracions < ActiveRecord::Migration[7.0]
  def change
    create_table :ubicacion_configuracions do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.string :ubicacion
      t.string :configuracion
      t.text :actividades_colindantes
      t.text :comentarios_generales

      t.timestamps
    end
  end
end
