class CreatePolicyAnalyses < ActiveRecord::Migration[7.0]
  def change
    create_table :policy_analyses do |t|
      t.references :user, null: false, foreign_key: true
      t.json :extractions
      t.json :rating

      t.timestamps
    end
  end
end
