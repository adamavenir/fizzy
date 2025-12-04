class AddLastMutationTimestampToBoards < ActiveRecord::Migration[8.2]
  def change
    add_column :boards, :last_mutation_timestamp, :integer, limit: 8, default: 0, null: false
  end
end
