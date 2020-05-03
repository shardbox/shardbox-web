require "markd"
require "./util/html_resolve_links"
require "digest"

Crinja.filter({base_url: nil}, "markdown") do
  options = Markd::Options.new
  options.base_url = uri_from_value(arguments["base_url"])

  Crinja::SafeString.new(Markd.to_html(target.to_s, options))
end

Crinja.filter({repo_ref: Crinja::UNDEFINED, revision: nil}, "markdown_repo_content") do
  html = Markd.to_html(target.to_s)

  repo_ref = arguments["repo_ref"].raw.as(Repo::Ref)
  refname = arguments["revision"].as_s?

  Crinja::SafeString.build do |io|
    HTML.resolve_links(io, html,
      base_url_href: repo_ref.base_url_source(refname),
      base_url_src: repo_ref.base_url_raw(refname)
    )
  end
end

private def uri_from_value(value)
  case raw = value.raw
  when Nil
  when URI
    raw
  else
    URI.parse(value.as_s!)
  end
end

Crinja.filter("gravatar_hash") do
  mail = target.as_s!
  Digest::MD5.hexdigest(mail.strip.downcase)
end
