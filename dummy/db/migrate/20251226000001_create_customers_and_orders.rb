# frozen_string_literal: true

class CreateCustomersAndOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :name, null: false
      t.string :region, null: false
      t.timestamps
    end

    create_table :orders do |t|
      t.references :customer, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :status, null: false, default: "placed"
      t.datetime :ordered_at, null: false
      t.timestamps
    end

    add_index :orders, :ordered_at
  end
end
