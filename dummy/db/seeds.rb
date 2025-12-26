# frozen_string_literal: true

rng = Random.new(42)

first_names = %w[
  Alex Casey Chris Dana Eli Finn Harper Jamie Jordan Kai Logan Morgan Quinn Riley Sam Taylor
].freeze
last_names = %w[
  Adams Baker Carter Davis Edwards Flores Garcia Harris Jackson Kim Lopez Miller Nguyen Patel Reed Smith Turner
].freeze
regions = %w[North South East West].freeze
statuses = %w[placed shipped delivered refunded].freeze

if Customer.exists? || Order.exists?
  puts "Seed data already present, skipping."
  exit 0
end

customers =
  50.times.map do
    Customer.create!(
      name: "#{first_names.sample(random: rng)} #{last_names.sample(random: rng)}",
      region: regions.sample(random: rng),
      created_at: Time.current - rng.rand(10..90).days,
      updated_at: Time.current
    )
  end

600.times do
  ordered_at = Time.current - rng.rand(0..60).days - rng.rand(0..86_399).seconds
  Order.create!(
    customer: customers.sample(random: rng),
    amount_cents: rng.rand(500..50_000),
    status: statuses.sample(random: rng),
    ordered_at: ordered_at,
    created_at: ordered_at,
    updated_at: ordered_at
  )
end

puts "Seeded #{Customer.count} customers and #{Order.count} orders."
