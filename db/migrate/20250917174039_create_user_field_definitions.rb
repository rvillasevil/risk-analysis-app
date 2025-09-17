class CreateUserFieldDefinitions < ActiveRecord::Migration[7.0]
  def change
    create_table :user_field_definitions do |t|
      t.references :user_field_section, null: false, foreign_key: true
      t.string :field_key, null: false
      t.string :label, null: false
      t.text :prompt
      t.string :field_type, null: false, default: "string"
      t.jsonb :options, null: false, default: []
      t.text :example
      t.text :why
      t.text :context
      t.text :assistant_instructions
      t.text :normative_tips
      t.jsonb :validation, null: false, default: {}
      t.string :parent_field_key
      t.boolean :array_of_objects, null: false, default: false
      t.string :item_label_template
      t.string :array_count_source_field_key
      t.jsonb :row_index_path, null: false, default: []
      t.integer :position, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :user_field_definitions, [:user_field_section_id, :field_key], unique: true, name: "index_user_field_defs_on_section_and_field_key"
    add_index :user_field_definitions, [:user_field_section_id, :position], name: "index_user_field_defs_on_section_and_position"
  end
end
