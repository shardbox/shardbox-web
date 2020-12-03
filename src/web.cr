require "clear"
require "log"

require "./clear_models"
require "./crinja_lib"

Log.setup do |config|
  stdout = Log::IOBackend.new
  config.bind "*", :debug, stdout
  config.bind "sanitize.*", :warn, stdout

  # raven = Raven::LogBackend.new(
  #   capture_exceptions: true,
  #   record_breadcrumbs: true,
  # )
  # config.bind "*", :warn, raven
end

# initialize a pool of database connection:
Clear::SQL.init(ENV["DATABASE_URL"])

def crinja
  Page.crinja
end

require "kemal"
require "./page"
require "./controllers/*"

Kemal.run
