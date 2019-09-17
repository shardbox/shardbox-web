require "kemal"
require "crinja"
require "baked_file_system"
require "sass"
require "humanize_time"
require "shardbox-core/db"
require "shardbox-core/repo"
require "./db"
require "./raven"
require "./crinja_models"
require "./crinja_lib"

def crinja
  crinja = Crinja.new
  crinja.loader = Crinja::Loader::FileSystemLoader.new("app/views/")
  crinja

  crinja.filters["humanize_time_span"] = Crinja.filter({now: Time.utc_now}) do
    time = target.as_time
    now = arguments["now"].as_time
    formatted = HumanizeTime.distance_of_time_in_words(time, now)
    if time <= now
      "#{formatted} ago"
    else
      "in #{formatted}"
    end
  end

  crinja
end

get "/" do |context|
  ShardsDB.connect do |db|
    recent_shards = db.recent_shards
    dependent_shards = db.dependent_shards
    popular_shards = db.popular_shards
    dev_dependent_shards = db.dependent_shards(:development)

    template = crinja.get_template("home.html.j2")
    template.render({
      "recent_shards"        => recent_shards,
      "dependent_shards"     => dependent_shards,
      "popular_shards"       => popular_shards,
      "dev_dependent_shards" => dev_dependent_shards,
      "new_shards"           => db.new_shards,
      "stats"                => db.stats,
    })
  end
end

get "/stats" do |context|
  ShardsDB.connect do |db|
    template = crinja.get_template("stats.html.j2")
    template.render({
      "stats" => db.stats,
    })
  end
end

get "/categories" do |context|
  ShardsDB.connect do |db|
    template = crinja.get_template("categories/index.html.j2")
    template.render({
      "categories" => db.all_categories,
      "top_shards" => db.all_categories_top_shards,
    })
  end
end

get "/categories/:slug" do |context|
  slug = context.params.url["slug"]
  ShardsDB.connect do |db|
    category = db.find_category(slug)

    unless category
      halt context, 404
    end

    if slug == "Uncategorized"
      # category = Category.new("Uncategorized", "Uncategorized")
      category_id = nil
      entries_count = db.uncategorized_count
    else
      category_id = category.id
      entries_count = category.entries_count
    end

    template = crinja.get_template("categories/show.html.j2")
    template.render({
      "category"      => category,
      "entries_count" => entries_count,
      "shards"        => db.shards_in_category_with_releases(category_id),
    })
  end
end

get "/shards/:name" do |context|
  show_release(context)
end

get "/shards/:name/:version" do |context|
  show_release(context)
end

get "/style.css" do |context|
  context.response.headers["Content-Type"] = "text/css"
  Sass.compile_file("app/sass/main.sass", include_path: "app/sass/")
end

get "/deploy_status" do
  "OK"
end

get "/contribute" do
  template = crinja.get_template("pages/contribute.html.j2")
  template.render
end

get "/imprint" do
  template = crinja.get_template("pages/imprint.html.j2")
  template.render
end

get "/search" do |context|
  query = context.request.query_params["q"]? || ""

  ShardsDB.connect do |db|
    shards = db.search(query)

    template = crinja.get_template("search.html.j2")
    template.render({
      "query"  => query,
      "shards" => shards,
    })
  end
end

def show_release(context)
  name = context.params.url["name"]
  name, _, qualifier = name.partition('~')

  ShardsDB.connect do |db|
    shard = db.find_shard?(name, qualifier)

    unless shard
      unqualified_shard = db.find_shard?(name, "")

      if unqualified_shard
        context.redirect "/shards/#{name}", 301
        return
      else
        halt context, 404, "Shard not found"
      end
    end

    releases = db.all_releases(shard.id)

    version = context.params.url["version"]?
    if version
      release = releases.find { |r| r.version == version }

      unless release
        halt context, 404, "Release not available"
      end
    else
      release = releases.find(&.latest?) || releases.last?

      unless release
        halt context, 404, "Shard has no release"
      end
    end

    dependencies = db.dependencies(release.id, :runtime)
    dev_dependencies = db.dependencies(release.id, :development)
    dependents = db.dependents(shard.id)

    canonical_repo = db.find_canonical_repo(shard.id)
    metrics = db.get_current_metrics(shard.id)
    mirrors = db.find_mirror_repos(shard.id)

    homonymous_shards = db.find_homonymous_shards(shard.name).reject { |s| s.id == shard.id }

    template = crinja.get_template("releases/show.html.j2")
    template.render({
      "repo"              => canonical_repo,
      "metrics"           => metrics,
      "mirrors"           => mirrors,
      "release"           => release,
      "shard"             => shard,
      "dependencies"      => dependencies,
      "dev_dependencies"  => dev_dependencies,
      "dependents"        => dependents,
      "releases"          => releases,
      "categories"        => db.find_categories(shard.id),
      "homonymous_shards" => homonymous_shards,
    })
  end
end

Kemal.run
