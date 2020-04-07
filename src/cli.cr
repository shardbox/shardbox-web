require "./app"

# Explicitly initialize a connection before listening to HTTP requests in order
# to avoid deadlocks on setup_connection.
ShardsDB.connect do |db|
  puts db.connection.scalar("SELECT MAX(version) FROM schema_migrations").as(String)
end

Kemal.run
