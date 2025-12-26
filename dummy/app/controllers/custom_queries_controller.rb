# frozen_string_literal: true

class CustomQueriesController < ApplicationController
  def new
    @predicate = (params[:predicate].presence || "CustomReport").to_s
    @source = (params[:source].presence || default_source_for(@predicate)).to_s
  end

  def create
    @predicate = params[:predicate].to_s
    @source = params[:source].to_s

    query = LogicaRb::Rails.query(source: @source, predicate: @predicate, trusted: false)
    @sql = query.sql
    @result = query.result
    render :new
  rescue StandardError => e
    @error = e
    render :new, status: :unprocessable_entity
  end

  private

  def default_source_for(predicate)
    <<~LOGICA
      @Engine("sqlite");

      #{predicate}(customer_name:, total_cents:) :-
        `((select
            c.name as customer_name,
            sum(o.amount_cents) as total_cents
          from customers c
          join orders o on o.customer_id = c.id
          group by c.name
          order by total_cents desc
          limit 20))`(customer_name:, total_cents:);
    LOGICA
  end
end
