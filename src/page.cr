module Page
  class_getter crinja : Crinja = initialize_crinja

  def self.initialize_crinja
    crinja = Crinja.new
    crinja.loader = Crinja::Loader::FileSystemLoader.new("app/views/")

    crinja.filters["humanize_time_span"] = Crinja.filter({now: Time.utc}) do
      time = target.as_time
      now = arguments["now"].as_time
      formatted = HumanizeTime.distance_of_time_in_words(time, now)
      if time <= now
        "#{formatted} ago"
      else
        "in #{formatted}"
      end
    end

    crinja
  end

  macro included
    include Crinja::Object::Auto
  end

  getter context : Crinja::Context do
    Crinja::Context.new(crinja.context).tap do |context|
      context["page"] = self
      initialize_context(context)
    end
  end

  private def initialize_context(context)
  end

  def render(io : IO, template : String)
    render(io, crinja.get_template(template))
  end

  def render(io : IO, template)
    template.render(io, context)
  end
end
