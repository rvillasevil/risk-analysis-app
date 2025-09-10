class AddRoleCompanyNameOwnerToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :role, :integer, default: 0, null: false
    add_column :users, :company_name, :string
    add_reference :users, :owner, foreign_key: { to_table: :users }    
  end
end
