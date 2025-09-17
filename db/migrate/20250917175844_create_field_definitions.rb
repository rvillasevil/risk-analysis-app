class CreateFieldDefinitions < ActiveRecord::Migration[7.0]
  def change
    create_table :field_definitions do |t|
      t.references :field_section, null: false, foreign_key: true
      t.string :identifier, null: false
      t.string :label, null: false
      t.text :prompt
      t.string :field_type, null: false, default: 'string'
      t.jsonb :options, null: false, default: []
      t.text :example
      t.text :why
      t.text :context
      t.jsonb :validation, null: false, default: {}
      t.text :assistant_instructions
      t.text :normative_tips
      t.string :parent_identifier
      t.boolean :array_of_objects, null: false, default: false
      t.string :item_label_template
      t.string :array_count_source_field_id
      t.jsonb :row_index_path, null: false, default: []
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :field_definitions, [:field_section_id, :identifier], unique: true, name: 'index_field_definitions_on_section_and_identifier'
    add_index :field_definitions, :identifier
  end
end
