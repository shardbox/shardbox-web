require "./app"

case command = ARGV[0]?
when "assets:precompile"
  assets_precompile
else
  Kemal.run
end
