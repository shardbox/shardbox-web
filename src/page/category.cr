@[Crinja::Attributes]
struct Page::Category
  include Page

  getter category : ::Category
  getter entries : Array(::Shard)
  getter? uncategorized : Bool

  def initialize(@category)
    @uncategorized = category.slug == "Uncategorized"
    @entries = @category.shards.with_basic_info.to_a(fetch_columns: true)
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
    context["entries_count"] = entries.size
    #context["homonymous_shards"] = homonymous_shards
  end

  private def homonymous_shards
    #db.find_homonymous_shards(entries.map(&.shard.name))
  end

  def render(io)
    render(io, "categories/show.html.j2")
  end
end
