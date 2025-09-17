class CreateUserFieldSets < ActiveRecord::Migration[7.0]
  def change
    create_table :user_field_sets do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.text :description
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :user_field_sets, :user_id, where: "active", unique: true, name: "index_user_field_sets_on_user_id_active"
  end
end
