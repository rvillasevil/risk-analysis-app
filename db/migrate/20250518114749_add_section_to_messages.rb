class AddSectionToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :section, :string
  end
end
