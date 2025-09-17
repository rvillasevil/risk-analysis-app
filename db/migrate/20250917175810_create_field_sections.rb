class CreateFieldSections < ActiveRecord::Migration[7.0]
  def change
    create_table :field_sections do |t|
      t.references :field_catalogue, null: false, foreign_key: true
      t.string :identifier, null: false
      t.string :title, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :field_sections, [:field_catalogue_id, :identifier], unique: true, name: 'index_field_sections_on_catalogue_and_identifier'
  end
end
