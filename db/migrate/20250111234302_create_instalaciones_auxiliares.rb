class CreateInstalacionesAuxiliares < ActiveRecord::Migration[7.0]
  def change
    create_table :instalaciones_auxiliares do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.string :estado_sistema_electrico
      t.boolean :proteccion_electrica
      t.date :ultima_revision_electrica
      t.boolean :termografias
      t.integer :transformadores_numero
      t.decimal :transformadores_potencia
      t.decimal :calderas_potencia
      t.string :calderas_ubicacion
      t.boolean :calderas_critico
      t.decimal :frio_capacidad
      t.string :frio_uso
      t.integer :aire_compresores_numero
      t.decimal :aire_presion_maxima
      t.string :agua_almacenamiento
      t.decimal :agua_capacidad
      t.boolean :proteccion_incendios
      t.decimal :generadores_capacidad

      t.timestamps
    end
  end
end
