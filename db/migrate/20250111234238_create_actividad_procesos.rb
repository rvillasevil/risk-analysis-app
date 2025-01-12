class CreateActividadProcesos < ActiveRecord::Migration[7.0]
  def change
    create_table :actividad_procesos do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.string :actividad_principal
      t.string :actividad_secundaria
      t.integer :anio_inicio
      t.string :jornada_laboral
      t.decimal :produccion_anual
      t.decimal :facturacion_anual
      t.text :procesos_peligrosos
      t.string :certificaciones

      t.timestamps
    end
  end
end
