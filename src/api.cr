get "/api/v1/search" do |context|
  query = context.request.query_params["q"]? || ""

  ShardsDB.connect do |db|
    shards = db.search(query)

    JSON.build(context.response) do |json|
      json.object do
        json.field "query", query
        json.field "results" do
          json.array do
            shards.each do |entry|
              json.object do
                shard = entry[:shard]
                json.field "name", shard.name
                json.field "qualifier", shard.qualifier
                json.field "display_name", shard.display_name
                json.field "canonical_repo", entry[:repo].ref.to_uri.to_s
                json.field "description", shard.description
                json.field "latest_release" do
                  json.object do
                    json.field "version", entry[:version]
                    json.field "released_at", entry[:released_at]
                  end
                end
                json.field "details_url", "/shards/#{shard.slug}"
                json.field "categories" do
                  json.array do
                    entry[:categories].each do |category|
                      category.slug.to_json(json)
                    end
                  end
                end
                json.field "archived_at", shard.archived_at if shard.archived_at
              end
            end
          end
        end
      end
    end
  end
end

get "/api/v1/shards/:name" do |context|
  ShardsDB.connect do |db|
    page = Page::Shard.new(db, context, "json")
    case page
    when String
      halt context, 404, page
    when Nil
      next
    when Page::Shard
      page.to_json(context.response)
      nil
    end
  end
end

get "/api/v1/shards/:name/releases" do |context|
  ShardsDB.connect do |db|
    page = Page::Shard.new(db, context, "releases")
    case page
    when String
      halt context, 404, page
    when Nil
      next
    when Page::Shard
      JSON.build(context.response) do |json|
        json.object do
          shard = page.shard
          json.field "name", shard.name
          json.field "display_name", shard.display_name
          json.field "details_url", "/shards/#{shard.slug}"
          json.field "canonical_repo", page.canonical_repo.ref.to_uri.to_s

          json.field "releases" do
            json.array do
              page.all_releases.each do |release|
                json.object do
                  json.field "version", release.version
                  json.field "released_at", release.released_at
                  json.field "commit_hash", release.commit_hash
                end
              end
            end
          end
        end
      end
      nil
    end
  end
end
