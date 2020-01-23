@[Crinja::Attributes]
struct Page::Category
  include Page

  getter db : ShardsDB
  getter category : ::Category
  getter entries : Array(ShardsDB::CategoryResult)
  getter? uncategorized : Bool

  def initialize(@db, @category)
    @uncategorized = category.slug == "Uncategorized"
    @entries = @db.shards_in_category_with_releases(uncategorized? ? nil : category.id)
  end

  private def initialize_context(context)
    context["category"] = category
    context["shards"] = entries

    if uncategorized?
      initialize_context_uncategorized(context)
    else
      context["entries_count"] = category.entries_count
    end
  end

  private def initialize_context_uncategorized(context)
    context["entries_count"] = @db.uncategorized_count
    context["homonymous_shards"] = homonymous_shards
  end

  private def homonymous_shards
    db.find_homonymous_shards(entries.map(&.shard.name))
  end

  def render(io)
    render(io, "categories/show.html.j2")
  end
end
