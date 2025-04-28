class AddKeyandValueToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :key, :string
    add_column :messages, :value, :string
  end
end
