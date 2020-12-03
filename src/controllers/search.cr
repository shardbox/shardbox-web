get "/search" do |context|
  query = context.request.query_params["q"]? || ""

  shards = Shard.query.search(query).limit(50).to_a(fetch_columns: true)

  template = crinja.get_template("search.html.j2")
  template.render({
    "query"  => query,
    "shards" => shards,
  })
end
