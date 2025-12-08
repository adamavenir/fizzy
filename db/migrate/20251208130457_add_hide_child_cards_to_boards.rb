class AddHideChildCardsToBoards < ActiveRecord::Migration[8.2]
  def change
    add_column :boards, :hide_child_cards, :boolean, default: true, null: false
  end
end
