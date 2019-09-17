require "markd"

Crinja.filter("markdown") do
  Crinja::SafeString.new(Markd.to_html(target.to_s))
end
