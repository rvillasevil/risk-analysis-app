class AddFieldAskedToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :field_asked, :string
  end
end
