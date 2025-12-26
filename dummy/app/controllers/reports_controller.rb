# frozen_string_literal: true

class ReportsController < ApplicationController
  Report = Data.define(:id, :title, :file, :predicate, :description)

  REPORTS = [
    Report.new(
      id: "orders_by_day",
      title: "Orders by day",
      file: "reports/orders_by_day.l",
      predicate: "OrdersByDay",
      description: "Last 30 days: orders count + revenue."
    ),
    Report.new(
      id: "top_customers",
      title: "Top customers",
      file: "reports/top_customers.l",
      predicate: "TopCustomers",
      description: "Top 20 customers by revenue."
    ),
    Report.new(
      id: "sales_by_region",
      title: "Sales by region",
      file: "reports/sales_by_region.l",
      predicate: "SalesByRegion",
      description: "Orders + revenue grouped by region."
    ),
  ].freeze

  def index
    @reports = REPORTS
  end

  def show
    @report = REPORTS.find { |r| r.id == params[:id].to_s }
    raise ActiveRecord::RecordNotFound, "Unknown report" unless @report

    query = LogicaRb::Rails.query(file: @report.file, predicate: @report.predicate)
    @sql = query.sql
    @result = query.result
  rescue StandardError => e
    @error = e
  end
end
