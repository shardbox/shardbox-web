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

  private def initialize_context(context)
    context["release"] = release
    context["shard"] = shard
    context["releases"] = all_releases.first(NUM_RELEASES_SHOWN)
    context["all_releases"] = all_releases
    context["remaining_releases_count"] = Math.max(0, all_releases.size - NUM_RELEASES_SHOWN)

    context["dependencies"] = db.dependencies(release.id, :runtime)
    context["dev_dependencies"] = db.dependencies(release.id, :development)

    dependents = db.dependents(shard.id)
    context["all_dependents"] = dependents
    context["dependents"] = dependents.first(NUM_DEPENDENTS_SHOWN)
    context["remaining_dependents_count"] = Math.max(0, dependents.size - NUM_DEPENDENTS_SHOWN)

    repo = db.find_canonical_repo(shard.id)
    context["repo"] = repo
    context["repo_owner"] = db.get_owner?(repo.ref)
    context["source_url"] = repo.ref.base_url_source(release.revision_info.commit.sha)
    context["metrics"] = db.get_current_metrics(shard.id)
    context["mirrors"] = db.find_mirror_repos(shard.id)

    context["homonymous_shards"] = db.find_homonymous_shards(shard.name).reject { |s| s[:shard].id == shard.id }

    context["categories"] = db.find_categories(shard.id)

    case @name
    when "activity"
      context["activities"] = db.get_activity(shard.id).group_by(&.created_at).values.reverse
    else
    end
  end

  def render(io)
    render(io, "releases/#{name}.html.j2")
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
end
