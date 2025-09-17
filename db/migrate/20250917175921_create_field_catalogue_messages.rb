class CreateFieldCatalogueMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :field_catalogue_messages do |t|
      t.references :field_catalogue, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :field_catalogue_messages, :role
  end
end
