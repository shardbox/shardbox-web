get "/contribute" do
  template = crinja.get_template("pages/contribute.html.j2")
  template.render
end

get "/imprint" do
  template = crinja.get_template("pages/imprint.html.j2")
  template.render
end
