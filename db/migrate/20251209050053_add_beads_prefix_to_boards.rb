class AddBeadsPrefixToBoards < ActiveRecord::Migration[8.2]
  def change
    add_column :boards, :beads_prefix, :string
    add_index :boards, :beads_prefix
  end
end
