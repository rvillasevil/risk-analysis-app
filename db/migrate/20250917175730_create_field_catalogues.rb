class CreateFieldCatalogues < ActiveRecord::Migration[7.0]
  def change
    create_table :field_catalogues do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: 'draft'
      t.string :thread_id
      t.jsonb :generated_catalogue, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :instructions_injected_at

      t.timestamps
    end

    add_index :field_catalogues, [:owner_id, :status]
  end
end
