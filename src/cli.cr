require "./app"

ShardsDB.connect do |db|
  puts db.connection.scalar("SELECT MAX(version) FROM schema_migrations", String)
end

Kemal.run
