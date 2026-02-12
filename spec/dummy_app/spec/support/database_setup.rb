# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    ActiveRecord::Base.connection.execute("PRAGMA foreign_keys = OFF")

    unless ActiveRecord::Base.connection.table_exists?("schema_migrations")
      ActiveRecord::Base.connection.create_table("schema_migrations", id: false) do |t|
        t.string "version", null: false
      end
      ActiveRecord::Base.connection.add_index("schema_migrations", "version", unique: true)
    end

    migration_files = Dir[Rails.root.join("db/migrate/*.rb")]
    migration_files.each do |file|
      version = File.basename(file).split("_").first
      result = ActiveRecord::Base.connection.select_values(
        "SELECT version FROM schema_migrations WHERE version = '#{version}'",
      )
      next if result.include?(version)

      load file
      migration_class_name = File.basename(file, ".rb").split("_").drop(1).map(&:camelize).join
      migration_class = migration_class_name.constantize
      migration_class.new.change

      ActiveRecord::Base.connection.execute(
        "INSERT INTO schema_migrations (version) VALUES ('#{version}')",
      )
    end

    ActiveRecord::Base.connection.execute("PRAGMA foreign_keys = ON")
  end
end
