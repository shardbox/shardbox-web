record Activity,
  event : String,
  created_at : Time = Time.utc,
  metadata : JSON::Any? = nil,
  shard_id : Int64? = nil,
  repo_ref : Repo::Ref? = nil,
  id : Int64? = nil do
end

require "shardbox-core/db"

class ShardsDB
  # self.statement_timeout = "30s"

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
      {shard: Shard.new(name, qualifier, description, archived_at, id: id), version: version, released_at: released_at, categories: categories}
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
    results = connection.query_all <<-SQL % (), as: {Int64, String, String, String?, Time?, Int32, Int32, Int32, Array(Array(String))?, String, Time}
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at,
        metrics.dependents_count, metrics.dev_dependents_count, metrics.transitive_dependents_count,
        (SELECT array_agg(ARRAY[categories.slug::text, categories.name::text]) FROM categories WHERE shards.categories @> ARRAY[categories.id]),
        releases.version, releases.released_at
      FROM shards
      JOIN releases ON releases.shard_id = shards.id AND latest
      JOIN shard_metrics_current AS metrics ON metrics.shard_id = shards.id
      ORDER BY #{column_name} DESC
      LIMIT 11
      SQL

    results.map do |result|
      id, name, qualifier, description, archived_at, dependents_count, dev_dependents_count, transitive_dependents_count, categories, version, released_at = result
      categories ||= [] of Array(String)
      categories = categories.map { |(name, slug)| Category.new(name, slug) }
      {
        shard:                       Shard.new(name, qualifier, description, archived_at, id: id),
        dependents_count:            dependents_count,
        dev_dependents_count:        dev_dependents_count,
        transitive_dependents_count: transitive_dependents_count,
        categories:                  categories,
        version:                     version,
        released_at:                 released_at,
      }
    end
  end

  def popular_shards
    results = connection.query_all <<-SQL % (), as: {Int64, String, String, String?, Time?, Int32, Int32, Int32, Array(Array(String))?, String, Time}
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at,
        metrics.dependents_count, metrics.dev_dependents_count, metrics.transitive_dependents_count,
        (SELECT array_agg(ARRAY[categories.slug::text, categories.name::text]) FROM categories WHERE shards.categories @> ARRAY[categories.id]),
        releases.version, releases.released_at
      FROM shards
      JOIN releases ON releases.shard_id = shards.id AND latest
      JOIN shard_metrics_current AS metrics ON metrics.shard_id = shards.id
      ORDER BY popularity DESC
      LIMIT 11
      SQL

    results.map do |result|
      id, name, qualifier, description, archived_at, dependents_count, dev_dependents_count, transitive_dependents_count, categories, version, released_at = result
      categories ||= [] of Array(String)
      categories = categories.map { |(name, slug)| Category.new(name, slug) }
      {
        shard:                       Shard.new(name, qualifier, description, archived_at, id: id),
        dependents_count:            dependents_count,
        dev_dependents_count:        dev_dependents_count,
        transitive_dependents_count: transitive_dependents_count,
        categories:                  categories,
        version:                     version,
        released_at:                 released_at,
      }
    end
  end

  def shards_owned_by(owner_id : Int64)
    results = connection.query_all <<-SQL, owner_id, as: {Int64, String, String, String?, Time?, Int32, Int32, Int32, Array(Array(String))?, String, Time}
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at,
        metrics.dependents_count, metrics.dev_dependents_count, metrics.transitive_dependents_count,
        (SELECT array_agg(ARRAY[categories.slug::text, categories.name::text]) FROM categories WHERE shards.categories @> ARRAY[categories.id]),
        releases.version, releases.released_at
      FROM shards
      JOIN repos
        ON repos.shard_id = shards.id
        AND repos.role = 'canonical'
      JOIN releases
        ON releases.shard_id = shards.id AND latest
      JOIN shard_metrics_current AS metrics
        ON metrics.shard_id = shards.id
      WHERE owner_id = $1
      ORDER BY popularity DESC
      SQL

    results.map do |result|
      id, name, qualifier, description, archived_at, dependents_count, dev_dependents_count, transitive_dependents_count, categories, version, released_at = result
      categories ||= [] of Array(String)
      categories = categories.map { |(name, slug)| Category.new(name, slug) }
      {
        shard:                       Shard.new(name, qualifier, description, archived_at, id: id),
        dependents_count:            dependents_count,
        dev_dependents_count:        dev_dependents_count,
        transitive_dependents_count: transitive_dependents_count,
        version:                     version,
        released_at:                 released_at,
        categories:                  categories,
      }
    end
  end

  def get_owner_metrics(owner_id : Int64)
    result = connection.query_one? <<-SQL, owner_id, as: {Int32, Int32, Int32, Int32, Int32, Int32, Int32, Float32}
      SELECT
        shards_count,
        dependents_count,
        transitive_dependents_count,
        dev_dependents_count,
        transitive_dependencies_count,
        dev_dependencies_count,
        dependencies_count,
        popularity
      FROM
        owners
      WHERE id = $1
        AND dependents_count IS NOT NULL
      SQL

    return unless result
    Repo::Owner::Metrics.new(*result, nil)
  end

  def get_owners
    results = connection.query_all <<-SQL, as: {String, String, String?, String?, JSON::Any, Int64, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Float32}
      SELECT
        owners.resolver::text,
        owners.slug::text,
        owners.name,
        owners.description,
        owners.extra,
        owners.id,
        shards_count,
        dependents_count,
        transitive_dependents_count,
        dev_dependents_count,
        transitive_dependencies_count,
        dev_dependencies_count,
        dependencies_count,
        popularity
      FROM owners
      WHERE popularity IS NOT NULL
      ORDER BY popularity DESC
      LIMIT 100
      SQL

    results.map do |result|
      resolver, slug, name, description, extra, id, shards_count, dependents_count, transitive_dependents_count, dev_dependents_count, transitive_dependencies_count, dev_dependencies_count, dependencies_count, popularity = result

      {
        owner:   Repo::Owner.new(resolver, slug, name, description, extra.as_h, id: id),
        metrics: Repo::Owner::Metrics.new(shards_count, dependents_count, transitive_dependents_count, dev_dependents_count, transitive_dependencies_count, dev_dependencies_count, dependencies_count, popularity),
      }
    end
  end

  # SHARD

  def find_shard?(name : String, qualifier : String)
    result = connection.query_one? <<-SQL, name, qualifier, as: {Int64, String, String, String?, Time?, Int64?}
      SELECT id, name::text, qualifier::text, description, archived_at, merged_with
      FROM shards
      WHERE
        name = $1 AND qualifier = $2;
      SQL

    return unless result

    id, name, qualifier, description, archived_at, merged_with = result
    Shard.new(name, qualifier, description, archived_at, merged_with, id: id)
  end

  def find_homonymous_shards(name : String)
    results = [] of {shard: Shard, repo_ref: Repo::Ref, category: String?}
    connection.query_all <<-SQL, name do |result|
      SELECT shards.id, shards.name::text, qualifier::text, shards.description, archived_at,
      resolver::text, url::text, categories.slug::text
      FROM shards
      JOIN repos
        ON repos.shard_id = shards.id
        AND repos.role = 'canonical'
      LEFT JOIN categories
        ON categories.id = shards.categories[1]
      WHERE
        shards.name = $1;
      SQL
      id, name, qualifier, description, archived_at, resolver, url, category = result.read Int64, String, String, String?, Time?, String, String, String?
      results << {shard: Shard.new(name, qualifier, description, archived_at, id: id), repo_ref: Repo::Ref.new(resolver, url), category: category}
    end
    results
  end

  def find_homonymous_shards(names)
    results = {} of String => Array(Shard)
    connection.query_all <<-SQL, names do |result|
      SELECT
        id,
        name::text,
        qualifier::text,
        description,
        archived_at
      FROM
        shards
      WHERE
        name = ANY($1)
      ORDER BY
        name,
        qualifier
      SQL
      id, name, qualifier, description, archived_at = result.read Int64, String, String, String?, Time?
      list = results[name] ||= [] of Shard
      list << Shard.new(name, qualifier, description, archived_at, id: id)
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
    results = {} of Int64 => Array(Shard)
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

      list = results[category_id] ||= [] of Shard
      list << Shard.new(name, qualifier)
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

  record CategoryResult, shard : Shard, repo : Repo, release : Release,
    dependents_count : Int32?,
    dev_dependents_count : Int32?,
    transitive_dependents_count : Int32?

  def shards_in_category_with_releases(category_id : Int64?)
    if category_id
      args = [category_id]
      where = "$1 = ANY(categories)"
    else
      args = [] of Int64
      where = "categories = '{}'::bigint[]"
    end

    results = connection.query_all <<-SQL, args: args, as: {Int64, String, String, String?, Time?, String, Time, Int32?, Int32?, Int32?, String, String, String, Time?, Time?, Int64}
      SELECT
        shards.id, name::text, qualifier::text, shards.description, archived_at,
        releases.version, releases.released_at,
        metrics.dependents_count, metrics.dev_dependents_count, metrics.transitive_dependents_count,
        repos.resolver::text, repos.url::text, repos.metadata::text, repos.synced_at, repos.sync_failed_at, repos.id
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
      shard_id, name, qualifier, description, archived_at, version, released_at, dependents_count, dev_dependents_count, transitive_dependents_count, resolver, url, metadata, synced_at, sync_failed_at, repo_id = result
      CategoryResult.new(
        shard: Shard.new(name, qualifier, description, archived_at, id: shard_id),
        repo: Repo.new(resolver, url, shard_id,
          metadata: Repo::Metadata.from_json(metadata),
          synced_at: synced_at,
          sync_failed_at: sync_failed_at,
          id: repo_id),
        release: Release.new(version, released_at),
        dependents_count: dependents_count,
        dev_dependents_count: dev_dependents_count,
        transitive_dependents_count: transitive_dependents_count,
      )
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
        metrics.popularity DESC
      LIMIT 100
      SQL

    results.map do |result|
      shard_id, name, qualifier, description, archived_at, version, released_at, resolver, url, metadata, categories = result
      categories ||= [] of Array(String)
      categories = categories.map { |(name, slug)| Category.new(name, slug) }
      {shard: Shard.new(name, qualifier, description, archived_at, id: shard_id), repo: Repo.new(resolver, url, shard_id, metadata: Repo::Metadata.from_json(metadata)), version: version, released_at: released_at, categories: categories}
    end
  end

  # ACTIVITY
  def get_activity(shard_id : Int64)
    results = connection.query_all(<<-SQL, args: [shard_id], as: {Int64, Int64?, String, JSON::Any?, Time, Int64?, String?, String?})
        SELECT log.id, log.repo_id, log.event, log.metadata, log.created_at, log.shard_id,
          repos.url::text, repos.resolver::text
        FROM activity_log log
        LEFT JOIN repos
          ON repos.id = log.repo_id
        WHERE
          log.shard_id = $1
        SQL
    results.map do |result|
      id, repo_id, event, metadata, created_at, shard_id, url, resolver = result
      if resolver && url
        repo_ref = Repo::Ref.new(resolver, url)
      else
        repo_ref = nil
      end
      Activity.new(event, created_at, metadata, shard_id, repo_ref, id: id)
    end
  end

  # STATS

  def stats
    Stats.new(
      shards_count: connection.query_one("SELECT COUNT(*) FROM shards", as: Int64),
      repos_count: connection.query_one("SELECT COUNT(*) FROM repos WHERE role <> 'obsolete'", as: Int64),
      dependencies_count: connection.query_one(
        "SELECT COUNT(*) FROM dependencies JOIN releases ON release_id = releases.id WHERE releases.latest = true AND scope = 'runtime'", as: Int64),
      dev_dependencies_count: connection.query_one(
        "SELECT COUNT(*) FROM dependencies JOIN releases ON release_id = releases.id WHERE releases.latest = true AND scope = 'development'", as: Int64),
      resolver_counts: count_table("SELECT resolver::text, COUNT(*) AS count FROM repos GROUP BY resolver ORDER BY count DESC"),
      crystal_version_counts: count_table("SELECT spec->>'crystal' AS version, COUNT(*) AS count FROM releases WHERE latest = true GROUP BY spec->>'crystal' ORDER BY count DESC"),
      license_counts: count_table("SELECT spec->>'license', COUNT(*) FROM releases WHERE latest = true GROUP BY spec->>'license' ORDER BY count DESC"),
      uncategorized_count: uncategorized_count,
      shards_without_dependencies_count: connection.query_one("SELECT COUNT(*) FROM shards LEFT JOIN shard_dependencies ON shard_id = shards.id WHERE shard_dependencies.depends_on_repo_id IS NULL", as: Int64),
      shard_yml_keys_counts: count_table("SELECT jsonb_object_keys(spec) AS key, COUNT(*) AS count FROM releases WHERE latest GROUP BY key ORDER BY count DESC"),
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
    repos_count : Int64,
    dependencies_count : Int64,
    dev_dependencies_count : Int64,
    resolver_counts : Hash(String, Int64),
    crystal_version_counts : Hash(String, Int64),
    license_counts : Hash(String, Int64),
    uncategorized_count : Int64,
    shards_without_dependencies_count : Int64,
    shard_yml_keys_counts : Hash(String, Int64)
end
