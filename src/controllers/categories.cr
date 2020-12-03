get "/categories" do |context|
  template = crinja.get_template("categories/index.html.j2")
  template.render({
    "categories" => Category.all_with_top_shards.to_a(fetch_columns: true)
  })
end

get "/categories/:slug" do |context|
  slug = context.params.url["slug"]
    category = Category.find({slug: slug})

    unless category
      halt context, 404
    end

    page = Page::Category.new(category)
    page.render(context.response)
    nil
end
