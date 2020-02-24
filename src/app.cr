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
require "./page"
require "./page/*"

def crinja
  Page.crinja
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

    page = Page::Category.new(db, category)
    page.render(context.response)
    nil
  end
end

get "/shards/:name" do |context|
  show_release(context)
end

# Redirect /shards/:name/:version to /shards/releases/:version
get "/shards/:name/:version" do |context|
  # only redirect when version looks like a version
  unless context.params.url["version"] =~ /^\d+\.\d/
    halt context, 404
    next
  end

  ShardsDB.connect do |db|
    release = Page::Shard.find_release(db, context)
    case release
    when String
      halt context, 404, release
    when Nil
      next
    else
      # Found release, redirect to /releases/:version path
      context.redirect "/shards/#{context.params.url["name"]}/releases/#{context.params.url["version"]}"
    end
  end
end

get "/shards/:name/releases/:version" do |context|
  show_release(context)
end

get "/shards/:name/releases" do |context|
  ShardsDB.connect do |db|
    page = Page::Shard.new(db, context, "releases")
    case page
    when String
      halt context, 404, page
    when Nil
      next
    when Page::Shard
      page.render(context.response)
      nil
    end
  end
end

get "/shards/:name/releases/:version/dependencies" do |context|
  ShardsDB.connect do |db|
    page = Page::Shard.new(db, context, "dependencies")
    case page
    when String
      halt context, 404, page
    when Nil
      next
    when Page::Shard
      page.render(context.response)
      nil
    end
  end
end

get "/style.css" do |context|
  context.response.headers["Content-Type"] = "text/css"
  Sass.compile_file("app/sass/main.sass", is_indented_syntax_src: true, include_path: "app/sass/")
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

get "/webhook/import_catalog" do |context|
  secret = ENV["SHARDBOX_SECRET"]?
  unless secret
    halt context, status_code: HTTP::Status::NOT_FOUND.value
  end

  auth = context.request.headers["Authorization"]?
  unless auth
    context.response.headers["WWW-Authenticate"] = %[Basic realm="Webhook Authentication"]
    halt context, status_code: HTTP::Status::UNAUTHORIZED.value
  end

  unless auth == "Basic #{secret}"
    halt context, status_code: HTTP::Status::FORBIDDEN.value
  end

  ShardsDB.connect do |db|
    db.send_job_notification("import_catalog")
  end
end

def show_release(context)
  ShardsDB.connect do |db|
    page = Page::Shard.new(db, context, "readme")
    case page
    when String
      halt context, 404, page
    when Nil
      next
    when Page::Shard
      page.context["readme"] = db.fetch_file(page.release.id, "README.md")
      page.render(context.response, "releases/show.html.j2")
      nil
    end
  end
end

