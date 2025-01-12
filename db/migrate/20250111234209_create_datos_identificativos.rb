class CreateDatosIdentificativos < ActiveRecord::Migration[7.0]
  def change
    create_table :datos_identificativos do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.string :nombre
      t.string :direccion
      t.string :codigo_postal
      t.string :localidad
      t.string :provincia
      t.json :coordenadas
      t.date :fecha_inspeccion
      t.date :fecha_informe

      t.timestamps
    end
  end
end
