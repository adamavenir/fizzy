class CreateBeadsIssueStates < ActiveRecord::Migration[8.2]
  def change
    create_table :beads_issue_states, id: :uuid, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.uuid :board_id, null: false
      t.string :issue_id, limit: 255, null: false
      t.text :snapshot, null: false
      t.datetime :synced_at, null: false

      t.timestamps

      t.index [:board_id, :issue_id], unique: true
      t.index [:board_id], name: "index_beads_issue_states_on_board_id"
    end

    add_foreign_key :beads_issue_states, :boards
  end
end
