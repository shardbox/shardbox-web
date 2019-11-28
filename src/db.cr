class ShardsDB
  # HOME
  def recent_shards
    results = connection.query_all <<-SQL, as: {Int64, String, String, String?, Time?, String, Time, Array(Array(String))?}
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at, version, released_at,
        (SELECT array_agg(ARRAY[categories.slug::text, categories.name::text]) FROM categories WHERE shards.categories @> ARRAY[categories.id])
      FROM shards
      JOIN releases ON releases.shard_id = shards.id
      WHERE releases.latest = true
      ORDER BY releases.released_at DESC
      LIMIT 11
      SQL

    results.map do |result|
      id, name, qualifier, description, archived_at, version, released_at, categories = result
      categories ||= [] of Array(String)
      categories = categories.map { |(name, slug)| Category.new(name, slug) }
      {shard: Shard.new(name, qualifier, description, archived_at, id: id), version: version, released_at: released_at, categoires: categories}
    end
  end

  def new_shards
    results = connection.query_all <<-SQL, as: {Int64, String, String, String?, Time?, String, Time, String, String}
      WITH newest_shards AS (
        SELECT shard_id, MIN(released_at) AS released_at FROM releases WHERE version <> 'HEAD' GROUP BY shard_id ORDER BY MIN(released_at) DESC LIMIT 10
      )
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at,
        version, releases.released_at,
        repos.resolver::text, repos.url::text
      FROM
        shards
      JOIN
        releases ON releases.shard_id = shards.id
      JOIN
        repos ON repos.shard_id = shards.id AND repos.role = 'canonical'
      JOIN
        newest_shards ON newest_shards.shard_id = shards.id AND newest_shards.released_at = releases.released_at
      ORDER BY released_at DESC
      LIMIT 11
      SQL

    results.map do |result|
      id, name, qualifier, description, archived_at, version, created_at, resolver, url = result
      {shard: Shard.new(name, qualifier, description, archived_at, id: id), version: version, created_at: created_at, repo_ref: Repo::Ref.new(resolver, url)}
    end
  end

  def dependent_shards(scope : Dependency::Scope = :runtime)
    column_name = scope.development? ? "dev_dependents_count" : "dependents_count"
    results = connection.query_all <<-SQL % (), as: {Int64, String, String, String?, Time?, Int32, Array(Array(String))?, String, Time}
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at,
        metrics.#{column_name},
        (SELECT array_agg(ARRAY[categories.slug::text, categories.name::text]) FROM categories WHERE shards.categories @> ARRAY[categories.id]),
        releases.version, releases.released_at
      FROM shards
      JOIN releases ON releases.shard_id = shards.id AND latest
      JOIN shard_metrics_current AS metrics ON metrics.shard_id = shards.id
      ORDER BY #{column_name} DESC
      LIMIT 11
      SQL

    results.map do |result|
      id, name, qualifier, description, archived_at, num_dependencies, categories, version, released_at = result
      categories ||= [] of Array(String)
      categories = categories.map { |(name, slug)| Category.new(name, slug) }
      {shard: Shard.new(name, qualifier, description, archived_at, id: id), num_dependencies: num_dependencies, categories: categories, version: version, released_at: released_at}
    end
  end

  def popular_shards
    results = connection.query_all <<-SQL % (), as: {Int64, String, String, String?, Time?, Int32, Array(Array(String))?, String, Time}
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at,
        metrics.dependents_count,
        (SELECT array_agg(ARRAY[categories.slug::text, categories.name::text]) FROM categories WHERE shards.categories @> ARRAY[categories.id]),
        releases.version, releases.released_at
      FROM shards
      JOIN releases ON releases.shard_id = shards.id AND latest
      JOIN shard_metrics_current AS metrics ON metrics.shard_id = shards.id
      ORDER BY popularity DESC
      LIMIT 11
      SQL

    results.map do |result|
      id, name, qualifier, description, archived_at, num_dependencies, categories, version, released_at = result
      categories ||= [] of Array(String)
      categories = categories.map { |(name, slug)| Category.new(name, slug) }
      {shard: Shard.new(name, qualifier, description, archived_at, id: id), num_dependencies: num_dependencies, categories: categories, version: version, released_at: released_at}
    end
  end

  # SHARD

  def find_shard?(name : String, qualifier : String)
    result = connection.query_one? <<-SQL, name, qualifier, as: {Int64, String, String, String?, Time?}
      SELECT id, name::text, qualifier::text, description, archived_at
      FROM shards
      WHERE
        name = $1 AND qualifier = $2;
      SQL

    return unless result

    id, name, qualifier, description, archived_at = result
    Shard.new(name, qualifier, description, archived_at, id: id)
  end

  def find_homonymous_shards(name : String)
    results = [] of Shard
    connection.query_all <<-SQL, name do |result|
      SELECT id, name::text, qualifier::text, description, archived_at
      FROM shards
      WHERE
        name = $1;
      SQL
      id, name, qualifier, description, archived_at = result.read Int64, String, String, String?, Time?
      results << Shard.new(name, qualifier, description, archived_at, id: id)
    end
    results
  end

  def dependencies(release_id : Int64, scope : Dependency::Scope)
    results = connection.query_all <<-SQL, release_id, scope, as: {String, JSON::Any, String, Int64?, String?, String?, String?, Time?}
      SELECT
        dependencies.name::text, dependencies.spec, dependencies.scope::text,
        shards.id, shards.name::text, shards.qualifier::text, description::text, archived_at
      FROM
        dependencies
      LEFT JOIN
        repos ON dependencies.repo_id = repos.id
      JOIN
        shards ON repos.shard_id = shards.id
      WHERE
        dependencies.release_id = $1 AND dependencies.scope = $2
      SQL

    results.map do |result|
      name, spec, scope, shard_id, shard_name, qualifier, description, archived_at = result
      scope = Dependency::Scope.parse(scope)

      if shard_id
        shard = Shard.new(shard_name.not_nil!, qualifier.not_nil!, description, archived_at, id: shard_id)
      end

      {dependency: Dependency.new(name, spec, scope), shard: shard}
    end
  end

  def dependents(shard_id : Int64)
    results = connection.query_all <<-SQL, shard_id, as: {Int64, String, String, String?, Time?, Int32}
      SELECT
        shards.id, shards.name::text, shards.qualifier::text, description::text, archived_at,
        metrics.dependents_count
      FROM
        shards
      JOIN
        shard_dependencies ON shard_dependencies.shard_id = shards.id
      JOIN
        shard_metrics_current AS metrics ON metrics.shard_id = shards.id
      WHERE
        shard_dependencies.depends_on = $1
      ORDER BY
        metrics.dependents_count DESC, metrics.transitive_dependents_count DESC, metrics.dev_dependents_count DESC, shards.name ASC
      SQL

    results.map do |result|
      shard_id, shard_name, qualifier, description, archived_at, dependents_count = result

      {shard: Shard.new(shard_name, qualifier, description, archived_at, id: shard_id), dependents_count: dependents_count}
    end
  end

  def find_categories(shard_id : Int64)
    results = connection.query_all <<-SQL, shard_id, as: {Int64, String, String, String?, Int32}
      SELECT
        categories.id, categories.slug::text, categories.name::text, categories.description::text, categories.entries_count
      FROM
        categories
      JOIN
        shards ON shards.categories @> ARRAY[categories.id]
      WHERE shards.id = $1
      SQL

    results.map do |result|
      id, slug, name, description, entries_count = result

      Category.new(slug, name, description, entries_count, id: id)
    end
  end

  record Metrics, shard_id : Int64, popularity : Float32?, likes_count : Int32?, watchers_count : Int32?, forks_count : Int32?,
    clones_count : Int32?, dependents_count : Int32?, transitive_dependents_count : Int32?, dev_dependents_count : Int32?,
    transitive_dependencies_count : Int32?, dev_dependencies_count : Int32?, dependencies_count : Int32?, created_at : Time

  def get_current_metrics(shard_id : Int64)
    result = connection.query_one? <<-SQL, shard_id, as: {Float32?, Int32?, Int32?, Int32?, Int32?, Int32?, Int32?, Int32?, Int32?, Int32?, Int32?, Time}
      SELECT
        popularity, likes_count, watchers_count, forks_count,
        clones_count, dependents_count, transitive_dependents_count, dev_dependents_count,
        transitive_dependencies_count, dev_dependencies_count, dependencies_count, created_at
      FROM
        shard_metrics_current
      WHERE
        shard_id = $1
    SQL
    return unless result
    Metrics.new(shard_id, *result)
  end

  # CATEGORY

  def all_categories_top_shards
    results = Hash(Int64, Array(Shard)).new { |hash, key| hash[key] = [] of Shard }
    connection.query_all <<-SQL do |rs|
      SELECT
        *
      FROM
        (
          SELECT
            s.*,
            ROW_NUMBER() OVER (
              PARTITION BY
                category_id
              ORDER BY
                transitive_dependents_count DESC
            ) AS r
          FROM
            (
              SELECT
                unnest(categories) AS category_id,
                name::text, qualifier::text,
                shards.id
              FROM
                shards
              WHERE
                archived_at IS NULL
            ) s
          JOIN
            shard_metrics_current AS metrics ON s.id = metrics.shard_id
        ) x
      WHERE
        x.r <= 5
      SQL
      category_id, name, qualifier = rs.read Int64, String, String, Int64

      results[category_id] << Shard.new(name, qualifier)
    end
    results
  end

  def find_category(slug : String)
    result = connection.query_one? <<-SQL, slug, as: {Int64, String, String, String?, Int32}
      SELECT
        id, slug::text, name::text, description::text, entries_count
      FROM
        categories
      WHERE
        slug = $1
      SQL

    return unless result

    id, slug, name, description, entries_count = result

    Category.new(slug, name, description, entries_count, id: id)
  end

  def shards_in_category_with_releases(category_id : Int64?)
    if category_id
      args = [category_id]
      where = "$1 = ANY(categories)"
    else
      args = [] of Int64
      where = "categories = '{}'::bigint[]"
    end

    results = connection.query_all <<-SQL, args: args, as: {Int64, String, String, String?, Time?, String, Time, String, String, String, Time?, Time?, Int64, Array(Array(String))?}
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at,
        releases.version, releases.released_at,
        repos.resolver::text, repos.url::text, repos.metadata::text, repos.synced_at, repos.sync_failed_at, repos.id,
        (SELECT array_agg(ARRAY[categories.slug::text, categories.name::text]) FROM categories WHERE shards.categories @> ARRAY[categories.id])
      FROM
        shards
      JOIN
        releases ON releases.shard_id = shards.id AND releases.latest = true
      JOIN
        repos ON repos.shard_id = shards.id AND repos.role = 'canonical'
      LEFT JOIN
        shard_metrics_current AS metrics ON metrics.shard_id = shards.id
      WHERE
        #{where}
      ORDER BY
        metrics.popularity DESC
      SQL

    results.map do |result|
      shard_id, name, qualifier, description, archived_at, version, released_at, resolver, url, metadata, synced_at, sync_failed_at, repo_id, categories = result
      categories ||= [] of Array(String)
      categories = categories.map { |(name, slug)| Category.new(name, slug) }
      {
        shard: Shard.new(name, qualifier, description, archived_at, id: shard_id),
        repo:  Repo.new(resolver, url, shard_id,
          metadata: Repo::Metadata.from_json(metadata),
          synced_at: synced_at,
          sync_failed_at: sync_failed_at,
          id: repo_id),
        release: Release.new(version, released_at),
      }
    end
  end

  def duplicate_shard_names
    results = Hash(String, Array(String)).new { [] of String }
    connection.query_all <<-SQL do |rs|
      WITH qualified_shards AS (
        SELECT DISTINCT name FROM shards WHERE qualifier != ''
      )
      SELECT
        shards.name::text, qualifier::text
      FROM
        shards
      JOIN
        qualified_shards ON qualified_shards.name = shards.name
      ORDER BY
        name, qualifier
      SQL
      name, qualifier = rs.read String, String
      results[name] << qualifier
    end
    results
  end

  def search(query)
    query = "%#{query}%"
    results = connection.query_all <<-SQL, query, as: {Int64, String, String, String?, Time?, String, Time, String, String, String, Array(Array(String))?}
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at,
        releases.version, releases.released_at,
        repos.resolver::text, repos.url::text, repos.metadata::text,
        (SELECT array_agg(ARRAY[categories.slug::text, categories.name::text]) FROM categories WHERE shards.categories @> ARRAY[categories.id])
      FROM
        shards
      JOIN
        releases ON releases.shard_id = shards.id AND releases.id = (SELECT id FROM releases WHERE shard_id = shards.id ORDER BY latest, position LIMIT 1)
      JOIN
        repos ON repos.shard_id = shards.id AND repos.role = 'canonical'
      LEFT JOIN
        shard_metrics_current AS metrics ON metrics.shard_id = shards.id
      WHERE
        name LIKE $1 OR qualifier LIKE $1 OR shards.description LIKE $1 OR releases.spec->>'description' = $1 OR repos.metadata->>'description' = $1
      ORDER BY
        metrics.transitive_dependents_count DESC
      LIMIT 100
      SQL

    results.map do |result|
      shard_id, name, qualifier, description, archived_at, version, released_at, resolver, url, metadata, categories = result
      categories ||= [] of Array(String)
      categories = categories.map { |(name, slug)| Category.new(name, slug) }
      {shard: Shard.new(name, qualifier, description, archived_at, id: shard_id), repo: Repo.new(resolver, url, shard_id, metadata: Repo::Metadata.from_json(metadata)), version: version, released_at: released_at, categories: categories}
    end
  end

  # STATS

  def stats
    Stats.new(
      shards_count: connection.query_one("SELECT COUNT(*) FROM shards", as: Int64),
      dependencies_count: connection.query_one(
        "SELECT COUNT(*) FROM dependencies JOIN releases ON release_id = releases.id WHERE releases.latest = true AND scope = 'runtime'", as: Int64),
      dev_dependencies_count: connection.query_one(
        "SELECT COUNT(*) FROM dependencies JOIN releases ON release_id = releases.id WHERE releases.latest = true AND scope = 'development'", as: Int64),
      resolver_counts: count_table("SELECT resolver::text, COUNT(*) AS count FROM repos GROUP BY resolver ORDER BY count DESC"),
      crystal_version_counts: count_table("SELECT spec->>'crystal' AS version, COUNT(*) AS count FROM releases WHERE latest = true GROUP BY spec->>'crystal' ORDER BY count DESC"),
      license_counts: count_table("SELECT spec->>'license', COUNT(*) FROM releases WHERE latest = true GROUP BY spec->>'license' ORDER BY count DESC"),
      uncategorized_count: uncategorized_count,
      shards_without_dependencies_count: connection.query_one("SELECT COUNT(*) FROM shards LEFT JOIN shard_dependencies ON shard_id = shards.id WHERE shard_dependencies.depends_on_repo_id IS NULL", as: Int64),
    )
  end

  def uncategorized_count
    connection.query_one("SELECT COUNT(*) FROM shards WHERE categories = '{}'::bigint[]", as: Int64)
  end

  private def count_table(query)
    counts = {} of String => Int64
    connection.query(query) do |rs|
      rs.each do
        counts[rs.read(String?) || "none"] = rs.read(Int64)
      end
    end
    counts
  end

  record Stats,
    shards_count : Int64,
    dependencies_count : Int64,
    dev_dependencies_count : Int64,
    resolver_counts : Hash(String, Int64),
    crystal_version_counts : Hash(String, Int64),
    license_counts : Hash(String, Int64),
    uncategorized_count : Int64,
    shards_without_dependencies_count : Int64
end
