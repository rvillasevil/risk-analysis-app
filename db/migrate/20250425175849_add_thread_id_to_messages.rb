class AddThreadIdToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :thread_id, :string
  end
end
