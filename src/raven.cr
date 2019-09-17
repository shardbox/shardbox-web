require "raven"
require "raven/integrations/kemal"

# Perform basic raven configuration, none of it is required though
Raven.configure do |config|
  # Keep main fiber responsive by sending the events in the background
  config.async = true
  # Set the environment name using `Kemal.config.env`, which uses `KEMAL_ENV` variable under-the-hood
  config.current_environment = Kemal.config.env

  # If your requests are failing because of connection
  # timeout error, try setting bigger value
  # (defaults to `1.second`).
  #
  # NOTE: Avoid using bigger values without `#async` option enabled
  config.connect_timeout = 5.seconds

  # In case of hitting rate limit you might want to try
  # lower sample rate threshold, in this case to 75%
  config.sample_rate = 0.75

  # Remove default processors you don't need
  # config.processors -= [Raven::Processor::Cookies, Raven::Processor::RequestMethodData]

  # Ignore certain exception classes
  # `Kemal::Exceptions::RouteNotFound` is added automatically
  # config.excluded_exceptions << NotImplementedError

  # Sanitize additional fields
  # config.sanitize_fields << /\Aaddress_(.*?)\Z/i

  # Setup `#before_send` hook, which allows modifying
  # the event before sending, or dropping it entirely
  # config.before_send do |event, hint|
  #   # Group events by topic based on exception message
  #   if hint.try(&.exception).try(&.message) =~ /database unavailable/i
  #     event.fingerprint << "database-unavailable"
  #   end
  #   # Conditionally skip sending the event
  #   event unless ENV["CI"]? == "1"
  # end
end

# Replace the built-in `Kemal::LogHandler` with a
# dedicated `Raven::Kemal::LogHandler`, capturing all
# sent messages and requests as Sentry breadcrumbs

# If you'd like to preserve default logging provided by
# Kemal, pass `Kemal::LogHandler.new` to the constructor
if Kemal.config.logging
  Kemal.config.logger = Raven::Kemal::LogHandler.new(Kemal::LogHandler.new)
else
  Kemal.config.logger = Raven::Kemal::LogHandler.new
end

# Add raven's exception handler in order to capture
# all unhandled exceptions thrown inside your routes.
# Captured exceptions are re-raised afterwards
Kemal.config.add_handler Raven::Kemal::ExceptionHandler.new
