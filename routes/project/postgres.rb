# frozen_string_literal: true

class Clover
  hash_branch(:project_prefix, "postgres") do |r|
    r.get true do
      postgres_list
    end

    r.web do
      r.post true do
        check_visible_location
        postgres_post(typecast_params.nonempty_str("name"))
      end

      r.get "create" do
        authorize("Postgres:create", @project.id)

        flavor = typecast_params.nonempty_str("flavor", PostgresResource::Flavor::STANDARD)
        Validation.validate_postgres_flavor(flavor)

        @flavor = flavor
        @prices = fetch_location_based_prices("PostgresVCpu", "PostgresStorage")
        @has_valid_payment_method = @project.has_valid_payment_method?
        @enabled_postgres_sizes = Option::VmSizes.select { @project.quota_available?("PostgresVCpu", it.vcpus) }.map(&:name)
        @option_tree, @option_parents = generate_postgres_options(flavor: @flavor)

        view "postgres/create"
      end
    end
  end
end
