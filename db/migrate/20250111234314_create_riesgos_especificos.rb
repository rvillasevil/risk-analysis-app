class CreateRiesgosEspecificos < ActiveRecord::Migration[7.0]
  def change
    create_table :riesgos_especificos do |t|
      t.references :risk_assistant, null: false, foreign_key: true
      t.boolean :incendio
      t.boolean :robo
      t.boolean :interrupcion_negocio
      t.boolean :responsabilidad_civil
      t.text :riesgos_naturales
      t.text :otros_riesgos

      t.timestamps
    end
  end
end
