@[Crinja::Attributes]
struct Page::Shard
  include Page

  NUM_RELEASES_SHOWN   =  8
  NUM_DEPENDENTS_SHOWN = 10

  def self.new(db, context, name)
    result = find_release(db, context)
    return result if result.nil? || result.is_a?(String)

    new db, *result, name
  end

  getter db : ShardsDB
  getter shard : ::Shard
  getter all_releases : Array(Release)
  getter name : String
  @release : Release?

  def initialize(@db, @shard, @all_releases, @release, @name)
  end

  def release?
    @release
  end

  def release
    release? || default_release || raise "Shard #{shard.slug} has no releases"
  end

  def default_release
    all_releases.find(&.latest?) || all_releases.last?
  end

  def canonical_repo
    db.find_canonical_repo(shard.id)
  end

  def mirrors
    db.find_mirror_repos(shard.id)
  end

  def categories
    db.find_categories(shard.id)
  end

  def dependencies
    db.dependencies(release.id, :runtime)
  end

  def dev_dependencies
    db.dependencies(release.id, :development)
  end

  def owner
    db.get_owner?(canonical_repo.ref)
  end

  def source_url
    canonical_repo.ref.base_url_source(release.revision_info.commit.sha)
  end

  def path
    "/shards/#{shard.slug}"
  end

  private def initialize_context(context)
    context["release"] = release
    context["shard"] = shard
    context["releases"] = all_releases.first(NUM_RELEASES_SHOWN)
    context["all_releases"] = all_releases
    context["remaining_releases_count"] = Math.max(0, all_releases.size - NUM_RELEASES_SHOWN)

    context["dependencies"] = dependencies
    context["dev_dependencies"] = dev_dependencies

    dependents = db.dependents(shard.id)
    context["all_dependents"] = dependents
    context["dependents"] = dependents.first(NUM_DEPENDENTS_SHOWN)
    context["remaining_dependents_count"] = Math.max(0, dependents.size - NUM_DEPENDENTS_SHOWN)

    repo = canonical_repo
    context["repo"] = repo
    context["repo_owner"] = owner
    context["source_url"] = source_url
    context["metrics"] = db.get_current_metrics(shard.id)
    context["mirrors"] = mirrors

    context["homonymous_shards"] = db.find_homonymous_shards(shard.name).reject { |s| s[:shard].id == shard.id }

    context["categories"] = categories

    case @name
    when "activity"
      context["activities"] = db.get_activity(shard.id).group_by(&.created_at).values.reverse
    else
    end
  end

  def render(io)
    render(io, "releases/#{name}.html.j2")
  end

  def to_json(json : JSON::Builder)
    json.object do
      json.field "name", shard.name
      json.field "qualifier", shard.qualifier
      json.field "display_name", shard.display_name
      json.field "canonical_repo", canonical_repo.ref.to_uri.to_s
      json.field "description", shard.description
      json.field "categories" do
        json.array do
          categories.each do |category|
            category.slug.to_json(json)
          end
        end
      end
      json.field "archived_at", shard.archived_at if shard.archived_at
      if owner = self.owner
        json.field "owner" do
          json.object do
            json.field "resolver", owner.resolver
            json.field "slug", owner.slug
            json.field "name", owner.name
            json.field "description", owner.description if owner.description.presence
            json.field "website_url", owner.website_url if owner.website_url
          end
        end
      end
      json.field "latest_release" do
        default_release.to_json(json)
      end
      json.field "source_url", source_url.to_s if source_url
      json.field "mirrors" do
        json.array do
          mirrors.each do |mirror|
            mirror.ref.to_uri.to_s.to_json(json)
          end
        end
      end
    end
  end

  def self.find_release(db, context)
    name = context.params.url["name"]
    name, _, qualifier = name.partition('~')

    shard = db.find_shard?(name, qualifier)

    unless shard
      unqualified_shard = db.find_shard?(name, "")

      if unqualified_shard
        context.redirect "/shards/#{name}", 301
        return
      else
        return "Shard not found"
      end
    end

    if merged_with = shard.merged_with
      main_shard = db.get_shard(merged_with)
      context.redirect "/shards/#{main_shard.display_name}", 301
      return
    end

    releases = db.all_releases(shard.id)

    version = context.params.url["version"]?
    if version
      release = releases.find { |r| r.version == version }

      unless release
        return "Release not available"
      end
    else
      release = nil

      if releases.empty?
        return "Shard has no releases"
      end
    end

    return shard, releases, release
  end
end

class Release
  def spec_authors
    authors = [] of Author
    specs = spec["authors"]?.try(&.as_a?)
    return authors unless specs

    specs.each do |s|
      authors << Author.new(s.as_s)
    end

    authors
  end

  def to_json(json : JSON::Builder)
    json.object do
      json.field "version", version
      json.field "released_at", released_at
      json.field "revision_identifier", revision_identifier
      json.field "commit_hash", commit_hash
      json.field "revision_info", revision_info
      json.field "spec" do
        json.object do
          json.field "description", description
          json.field "license", license
          json.field "crystal", crystal
          json.field "authors", spec_authors
        end
      end
    end
  end

  def commit_hash : String?
    revision_info.try(&.commit.sha)
  end
end

struct Author
  getter name : String
  getter email : String?

  def initialize(@name : String)
    if name =~ /\A\s*(.+?)\s*<+(\s*.+?\s*)>/
      @name, @email = $1, $2
    else
      @name = name
    end
  end

  def to_json(json : JSON::Builder)
    json.object do
      json.field "name", name
      json.field "email", email if email
    end
  end
end
