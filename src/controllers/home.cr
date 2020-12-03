get "/" do |context|
  limit = 11

  template = crinja.get_template("home.html.j2")
  template.render({
    "recent_shards"        => Shard.recent.limit(limit).to_a(fetch_columns: true),
    "dependent_shards"     => Shard.dependent(Scope::Runtime).limit(limit).to_a(fetch_columns: true),
    "dev_dependent_shards" => Shard.dependent(Scope::Development).limit(limit).to_a(fetch_columns: true),
    "popular_shards"       => Shard.popular.limit(limit).to_a(fetch_columns: true),
    "new_shards"           => Shard.new_listed.limit(limit).to_a(fetch_columns: true),
    "stats"                => Stats.get,
  })
end

get "/stats" do |context|
  template = crinja.get_template("stats.html.j2")
  template.render({
    "stats" => Stats.get,
  })
end

@[Crinja::Attributes]
class Stats
  include Crinja::Object::Auto

  getter shards_count : Int64
  getter repos_count : Int64
  getter dependencies_count : Int64
  getter dev_dependencies_count : Int64
  getter resolver_counts : Hash(String, Int64)
  getter crystal_version_counts : Hash(String, Int64)
  getter license_counts : Hash(String, Int64)
  getter uncategorized_count : Int64
  getter shards_without_dependencies_count : Int64
  getter shard_yml_keys_counts : Hash(String, Int64)

  @@cache : Stats?

  def self.get(max_age = 10.minutes)
    if cache = @@cache
      if cache.@cached_at > Time.monotonic - max_age
        return cache
      end
    end

    @@cache = new
  end

  def initialize
    @shards_count = Clear::SQL.select("COUNT(*) FROM shards").scalar(Int64)
    @repos_count = Clear::SQL.select("COUNT(*) FROM repos WHERE role <> 'obsolete'").scalar(Int64)
    @dependencies_count = Clear::SQL.select(
        "COUNT(*) FROM dependencies JOIN releases ON release_id = releases.id WHERE releases.latest = true AND scope = 'runtime'").scalar(Int64)
    @dev_dependencies_count = Clear::SQL.select(
        "COUNT(*) FROM dependencies JOIN releases ON release_id = releases.id WHERE releases.latest = true AND scope = 'development'").scalar(Int64)
    @resolver_counts = count_table("resolver::text AS key, COUNT(*) AS count FROM repos GROUP BY resolver ORDER BY count DESC")
    @crystal_version_counts = count_table("spec->>'crystal' AS key, COUNT(*) AS count FROM releases WHERE latest = true GROUP BY spec->>'crystal' ORDER BY count DESC")
    @license_counts = count_table("spec->>'license' AS key, COUNT(*) AS  count FROM releases WHERE latest = true GROUP BY spec->>'license' ORDER BY count DESC")
    @uncategorized_count = Clear::SQL.select("COUNT(*) FROM shards WHERE categories = '{}'::bigint[]").scalar(Int64)
    @shards_without_dependencies_count = Clear::SQL.select("COUNT(*) FROM shards LEFT JOIN shard_dependencies ON shard_id = shards.id WHERE shard_dependencies.depends_on_repo_id IS NULL").scalar(Int64)
    @shard_yml_keys_counts = count_table("jsonb_object_keys(spec) AS key, COUNT(*) AS count FROM releases WHERE latest GROUP BY key ORDER BY count DESC")
    @cached_at = Time.monotonic
  end

  private def count_table(query)
    counts = {} of String => Int64
    Clear::SQL.select(query).fetch do |hash|
      counts[hash["key"].as(String?) || ""] = hash["count"].as(Int64)
    end
    counts
  end
end
