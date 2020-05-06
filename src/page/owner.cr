require "shardbox-core/repo/owner"

@[Crinja::Attributes]
struct Page::Owner
  include Page

  def self.new(db, context)
    owner = find_owner(db, context)
    return owner if owner.nil? || owner.is_a?(String)

    new db, owner
  end

  def initialize(@db : ShardsDB, @owner : Repo::Owner)
  end

  private def initialize_context(context)
    context["owner"] = @owner
    context["shards"] = @db.shards_owned_by(@owner.id)
    context["metrics"] = @db.get_owner_metrics(@owner.id)
  end

  def render(io)
    render(io, "owners/show.html.j2")
  end

  def self.find_owner(db, context)
    resolver = context.params.url["resolver"]
    slug = context.params.url["slug"]

    db.get_owner?(resolver, slug)
  end
end
