macro show_release(context)
  with_release(context) do
    page = Page::Shard.new(*release, "readme")
    page.context["readme"] = page.release.file("README.md").try &.content
    page.render(context.response, "releases/show.html.j2")
  end
end

macro with_release(context)
  release = find_release({{ context }})

  case release
  when String
    halt {{ context}}, 404, release
  when Nil
    next
  else
    {{ yield }}
    nil
  end
end

get "/shards/:name" do |context|
  show_release(context)
end

get "/shards/:name/releases/:version" do |context|
  show_release(context)
end

# Redirect /shards/:name/:version to /shards/releases/:version
get "/shards/:name/:version" do |context|
  # only redirect when version looks like a version
  unless context.params.url["version"] =~ /^\d+\.\d/
    halt context, 404
    next
  end

  with_release(context) do
    # Found release, redirect to /releases/:version path
    context.redirect "/shards/#{context.params.url["name"]}/releases/#{context.params.url["version"]}"
  end
end

get "/shards/:name/releases" do |context|
  with_release(context) do
    page = Page::Shard.new(*release, "releases")
    page.render(context.response)
    nil
  end
end

get "/shards/:name/activity" do |context|
  with_release(context) do
    page = Page::Shard.new(*release, "activity")
    page.render(context.response)
    nil
  end
end

get "/shards/:name/releases/:version/dependencies" do |context|
  with_release(context) do
    page = Page::Shard.new(*release, "dependencies")
    page.render(context.response)
    nil
  end
end

def find_release(context)
  name = context.params.url["name"]
  name, _, qualifier = name.partition('~')

  shard = Shard.by_name(name, qualifier).first

  unless shard
    unqualified_shard = Shard.by_name(name, "").first

    if unqualified_shard
      context.redirect "/shards/#{name}", 301
      return
    else
      return "Shard not found"
    end
  end

  if merged_with = shard.merged_with
    main_shard = Shard.find!({id: merged_with})
    context.redirect "/shards/#{main_shard.display_name}", 301
    return
  end

  releases = shard.releases.ordered

  version = context.params.url["version"]?
  if version
    release = releases.find({version: version})

    unless release
      return "Release not available"
    end
  else
    release = nil
  end

  releases = releases.to_a

  if releases.empty?
    return "Shard has no releases"
  end

  return shard, releases, release
end
