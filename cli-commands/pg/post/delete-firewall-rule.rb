# frozen_string_literal: true

UbiCli.on("pg").run_on("delete-firewall-rule") do
  desc "Delete a PostgreSQL firewall rule"

  banner "ubi pg (location/pg-name | pg-id) delete-firewall-rule rule-id"

  args 1

  run do |ubid|
    if ubid.include?("/")
      raise Rodish::CommandFailure, "invalid firewall rule id format"
    end

    delete(pg_path("/firewall-rule/#{ubid}")) do |data|
      ["Firewall rule, if it exists, has been scheduled for deletion"]
    end
  end
end
