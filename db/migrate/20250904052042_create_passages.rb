class CreatePassages < ActiveRecord::Migration[7.0]
  def change
    enable_extension "vector" unless extension_enabled?("vector")

    create_table :passages do |t|
      t.text :content, null: false
      t.vector :embedding, limit: 1536
      t.timestamps
    end

    add_index :passages, :embedding, using: :ivfflat, opclass: :vector_l2_ops    
  end
end
