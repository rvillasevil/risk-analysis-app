class AddItemLabelToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :item_label, :string
  end
end
