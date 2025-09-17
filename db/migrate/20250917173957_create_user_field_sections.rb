class CreateUserFieldSections < ActiveRecord::Migration[7.0]
  def change
    create_table :user_field_sections do |t|
      t.references :user_field_set, null: false, foreign_key: true
      t.string :key, null: false
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :user_field_sections, [:user_field_set_id, :key], unique: true, name: "index_user_field_sections_on_set_and_key"
    add_index :user_field_sections, [:user_field_set_id, :position], name: "index_user_field_sections_on_set_and_position"
  end
end
