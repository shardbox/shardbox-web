@[Crinja::Attributes]
struct Page::Owner
  include Page

  def initialize(@owner : ::Owner)
  end

  private def initialize_context(context)
    context["owner"] = @owner
    context["shards"] = @owner.shards.to_a
    #context["metrics"] = @db.get_owner_metrics(@owner.id)
  end

  def render(io)
    render(io, "owners/show.html.j2")
  end
end
