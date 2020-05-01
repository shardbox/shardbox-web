@[Crinja::Attributes]
class URI
  include Crinja::Object::Auto
end

@[Crinja::Attributes]
class Shard
  include Crinja::Object::Auto

  @[Crinja::Attribute]
  def archived
    archived?
  end
end

@[Crinja::Attributes]
class Category
  include Crinja::Object::Auto
end

@[Crinja::Attributes]
struct ShardsDB::CategoryResult
  include Crinja::Object::Auto

  @[Crinja::Attribute(ignore: true)]
  def clone
    previous_def
  end
end

@[Crinja::Attributes(exclude: scope)]
class Dependency
  include Crinja::Object::Auto

  @[Crinja::Attribute(ignore: true)]
  def scope : Scope
    previous_def
  end

  def crinja_attribute(attr : Crinja::Value)
    if attr.to_string == "scope"
      return Crinja::Value.new(scope.to_s)
    end

    super
  end
end

@[Crinja::Attributes]
class Release
  include Crinja::Object::Auto

  def crinja_attribute(attr : Crinja::Value)
    case attr.to_string
    when "latest"
      Crinja::Value.new(latest?)
    when "yanked_at"
      Crinja::Value.new(yanked_at?)
    else
      super
    end
  end

  @[Crinja::Attributes]
  struct RevisionInfo
    include Crinja::Object::Auto
  end

  @[Crinja::Attributes]
  struct Commit
    include Crinja::Object::Auto
  end

  @[Crinja::Attributes]
  struct Tag
    include Crinja::Object::Auto
  end

  @[Crinja::Attributes]
  struct Signature
    include Crinja::Object::Auto
  end
end

@[Crinja::Attributes]
class Repo
  include Crinja::Object::Auto

  def crinja_attribute(attr : Crinja::Value)
    if attr.to_string == "role"
      return Crinja::Value.new(role.to_s)
    end

    super
  end
end

@[Crinja::Attributes]
struct Repo::Ref
  include Crinja::Object::Auto
end

@[Crinja::Attributes]
struct Repo::Metadata
  include Crinja::Object::Auto
end

@[Crinja::Attributes]
struct ShardsDB::Stats
  include Crinja::Object::Auto
end

@[Crinja::Attributes]
struct ShardsDB::Metrics
  include Crinja::Object::Auto
end

@[Crinja::Attributes]
struct Activity
  include Crinja::Object::Auto
  @[Crinja::Attribute(ignore: true)]
  def clone
    previous_def
  end
end
