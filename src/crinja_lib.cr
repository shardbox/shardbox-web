require "markd"

Crinja.filter({base_url: nil}, "markdown") do
  options = Markd::Options.new
  options.base_url = uri_from_value(arguments["base_url"])

  Crinja::SafeString.new(Markd.to_html(target.to_s, options))
end

Crinja.filter({repo_ref: Crinja::UNDEFINED, revision: nil}, "markdown_repo_content") do
  options = Markd::Options.new
  options.shardbox_repo_ref = arguments["repo_ref"].raw.as(Repo::Ref)
  options.shardbox_repo_version = arguments["revision"].as_s?.try(&.to_s)

  Crinja::SafeString.new(Markd.to_html(target.to_s, options))
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

struct Markd::Options
  property shardbox_repo_ref : Repo::Ref?
  property shardbox_repo_version : String?
end

class Markd::HTMLRenderer
  private def resolve_uri(destination, node)
    base_url = base_url(node) || @options.base_url
    return destination unless base_url

    uri = URI.parse(destination)
    return destination if uri.absolute?

    base_url.resolve(uri).to_s
  end

  private def base_url(node)
    repo_ref = @options.shardbox_repo_ref
    return unless repo_ref

    version = @options.shardbox_repo_version || "master"
    base_url = repo_ref.to_uri
    if node.type.image?
      base_url.path += "/raw/#{version}/"
    else
      if repo_ref.resolver == "bitbucket"
        base_url.path += "/src/#{version}/"
      else
        base_url.path += "/blob/#{version}/"
      end
    end
    base_url
  end
end
