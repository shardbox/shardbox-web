macro with_owner(context)
  owner = find_owner({{ context}})
  case owner
  when String
    halt context, 404, owner
  when Nil
    next
  else
    {{ yield }}
  end
end

get "/owners/" do |context|
  template = crinja.get_template("owners/index.html.j2")
  template.render({
    "owners" => Owner.query.to_a
  })
end

get "/owners/:resolver/:slug" do |context|
  with_owner(context) do
    page = Page::Owner.new(owner)
    page.render(context.response)
    nil
  end
end

def find_owner(context)
  resolver = context.params.url["resolver"]
  slug = context.params.url["slug"]

  Owner.find({resolver: resolver, slug: slug})
end
