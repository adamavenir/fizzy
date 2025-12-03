class AddRepoPathToBoards < ActiveRecord::Migration[8.2]
  def change
    add_column :boards, :repo_path, :string
  end
end
