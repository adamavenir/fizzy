class AddColumnTypeToColumns < ActiveRecord::Migration[8.2]
  def change
    add_column :columns, :column_type, :integer, default: 0, null: false
    add_column :columns, :beads_value, :string
  end
end
