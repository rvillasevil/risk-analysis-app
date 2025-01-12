class CreateEdificiosConstruccions < ActiveRecord::Migration[7.0]
  def change
    create_table :edificios_construccions do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.decimal :superficie_construida
      t.decimal :superficie_parcela
      t.integer :anio_construccion
      t.string :regimen_propiedad
      t.boolean :espacios_confinados
      t.boolean :galerias_subterraneas
      t.text :elementos_combustibles

      t.timestamps
    end
  end
end
