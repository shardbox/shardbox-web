require "crinja"
require "memory_cache"
require "clear"

abstract struct Clear::Enum
  include Crinja::Object::Auto
end

Clear.enum Scope, "runtime", "development"

@[Crinja::Attributes]
class Shard
  include Clear::Model
  include Crinja::Object::Auto

  column id : Int64, primary: true, presence: false

  column name : String
  column qualifier : String
  column description : String?
  column archived_at : Time?
  column merged_with : Int64?
  column category_ids : Array(Int64), column_name: "categories"

  column created_at : Time, presence: false
  column updated_at : Time, presence: false

  has_one metrics : ShardMetrics?
  has_many releases : Release
  has_many repos : Repo

  def mirrors
    repos.mirror
  end

  @[Crinja::Attributes]
  class ShardDependency
    include Clear::Model
    include Crinja::Object::Auto
    self.table = "shard_dependencies"

    belongs_to dependency : Shard?, foreign_key: "depends_on"
    belongs_to dependency_repo : Repo, foreign_key: "depends_on_repo"
    belongs_to shard : Shard

    column scope : Scope

    scope :development do
      where(scope: Scope::Development)
    end

    scope :runtime do
      where(scope: Scope::Runtime)
    end
  end

  has_many dependents : ShardDependency, foreign_key: "depends_on"
  has_many dependencies : ShardDependency

  scope :by_name do |name, qualifier|
    active
      .where(name: name, qualifier: qualifier)
  end

  scope :recent do
    active
      .inner_join("shard_metrics_current metrics", "metrics.shard_id = shards.id")
      .select("metrics.*")
      .order_by("releases.released_at", :desc)
      .with_basic_info
  end

  scope :new_listed do
    active
      .with_basic_info
      .inner_join("shard_metrics_current metrics", "metrics.shard_id = shards.id")
      .select("metrics.*")
      .with_cte(
        "newest_shards",
        Release.query
          .select("shard_id, MIN(released_at) AS released_at")
          .where("version <> 'HEAD'")
          .group_by("shard_id")
          .order_by("2", :desc)
      )
      .inner_join("newest_shards", "newest_shards.shard_id = shards.id AND newest_shards.released_at = releases.released_at")
      .order_by("newest_shards.released_at", :desc)
  end

  scope :popular do
    active
      .inner_join("shard_metrics_current metrics", "metrics.shard_id = shards.id")
      .select("metrics.*")
      .order_by("popularity", :desc)
      .with_basic_info
  end

  scope :dependent do |scope|
    column_name = scope == Scope::Development ? "dev_dependents_count" : "dependents_count"
    active
      .left_join("shard_metrics_current metrics", "metrics.shard_id = shards.id")
      .select("metrics.*")
      .order_by("metrics.#{column_name}", :desc)
      .with_basic_info
  end

  scope :with_basic_info do
    active
      .inner_join("releases", "releases.shard_id = shards.id AND releases.latest")
      .select("shards.*", "releases.released_at", "releases.version")
  end

  scope :search do |query|
    query = "%#{query}%"
    active
      .left_join("shard_metrics_current metrics", "metrics.shard_id = shards.id")
      .select("metrics.*")
      .inner_join("repos", "repos.shard_id = shards.id AND repos.role = 'canonical'")
      .where("name LIKE ? OR qualifier LIKE ? OR shards.description LIKE ? OR releases.spec->>'description' LIKE ? OR repos.metadata->>'description' LIKE ?", query, query, query, query, query)
      .order_by("metrics.popularity", :desc)
      .with_basic_info
  end

  scope :homonymous do |shard|
    active
      .where("shards.name = ? AND shards.id <> ?", shard.name, shard.id)
      .inner_join("repos", "repos.shard_id = shards.id AND repos.role = 'canonical'")
      .select("shards.*, repos.resolver::text, repos.url::text")
  end

  scope :active do
    where("archived_at IS NULL")
  end

  def version
    attributes["version"]?.as?(String)
  end

  def released_at
    attributes["released_at"]?.as?(Time)
  end

  def dependents_count
    attributes["dependents_count"]?.as?(Int32)
  end

  def dev_dependents_count
    attributes["dev_dependents_count"]?.as?(Int32)
  end

  def transitive_dependents_count
    attributes["transitive_dependents_count"]?.as?(Int32)
  end

  def repo_ref
    resolver = attributes["resolver"]?.as?(String)
    url = attributes["url"]?.as?(String)
    p! attributes, resolver, url
    if resolver && url
      Repo::Ref.new resolver, url
    end
  end

  # scope :new do
  #   with_releases.where("releases.latest").order_by("releases.released_at", :desc)
  # end

  def display_name
    if qualifier.empty?
      name
    else
      "#{name}~#{qualifier}"
    end
  end

  def slug
    display_name.downcase
  end

  def canonical_repo
    repos.canonical.first!
  end

  def categories
    category_ids.map { |id| Category.by_id(id) }
  end
end

@[Crinja::Attributes]
class Category
  include Clear::Model
  include Crinja::Object::Auto

  CACHE = MemoryCache(Int64, Category).new

  primary_key
  column name : String
  column slug : String
  column description : String?
  column entries_count : Int32

  def self.by_id(id : Int64)
    if category = CACHE.read(id)
      return category
    end
    fill_cache

    CACHE.read(id) || Category.query.find!({id: id})
  end

  private def self.fill_cache
    Category.query.each do |category|
      CACHE.write(category.id, category, expires_in: 15.minutes)
    end
  end

  def self.all_with_top_shards(limit = 5)
    shard_names = Shard.query
      .select("name || '~' || qualifier")
      .inner_join("shard_metrics_current AS metrics", "shards.id = metrics.shard_id")
      .where("categories.id = ANY(categories) AND archived_at IS NULL")
      .order_by("transitive_dependents_count", :desc)
      .limit(limit)

    Category.query
      .select("categories.*")
      .select("ARRAY(#{shard_names.to_sql}) AS top_shards")
      .order_by("name", :asc)
  end

  def top_shards
    top_shards = attributes["top_shards"]?
    return unless top_shards

    top_shards = top_shards.as?(Array(PG::StringArray)) || [] of PG::StringArray
    top_shards.map do |string|
      name, _, qualifier = string.to_s.partition("~")
      {name: name, qualifier: qualifier, slug: string.to_s.rchop("~")}
    end
  end

  def shards
    Shard.query
      .where("#{id} = ANY(categories) AND archived_at IS NULL")
  end
end

@[Crinja::Attributes]
class ShardMetrics
  include Clear::Model
  include Crinja::Object::Auto

  self.table = "shard_metrics_current"

  primary_key
  belongs_to shard : Shard

  column popularity : Int32?
  column likes_count : Int32?
  column watchers_count : Int32?
  column forks_count : Int32?
  column clones_count : Int32?
  column dependents_count : Int32?
  column transitive_dependents_count : Int32?
  column dev_dependents_count : Int32?
  column transitive_dependencies_count : Int32?
  column dev_dependencies_count : Int32?
  column dependencies_count : Int32?
  column created_at : Time, presence: false
end

Clear.enum Role, "canonical", "mirror", "legacy", "obsolete"#

@[Crinja::Attributes]
class Repo
  include Clear::Model
  include Crinja::Object::Auto

  RESOLVERS = {"git", "github", "gitlab", "bitbucket"}

  @[Crinja::Attributes]
  record Metadata,
    forks_count : Int32? = nil,
    stargazers_count : Int32? = nil,
    watchers_count : Int32? = nil,
    created_at : Time? = nil,
    description : String? = nil,
    issues_enabled : Bool? = nil,
    wiki_enabled : Bool? = nil,
    homepage_url : String? = nil,
    archived : Bool? = nil,
    fork : Bool? = nil,
    mirror : Bool? = nil,
    license : String? = nil,
    primary_language : String? = nil,
    pushed_at : Time? = nil,
    closed_issues_count : Int32? = nil,
    open_issues_count : Int32? = nil,
    closed_pull_requests_count : Int32? = nil,
    open_pull_requests_count : Int32? = nil,
    merged_pull_requests_count : Int32? = nil,
    topics : Array(String)? = nil do
    include JSON::Serializable
    include Crinja::Object::Auto
  end

  primary_key
  belongs_to shard : Shard
  has_many dependents : Dependency

  belongs_to owner : ::Owner?
  column resolver : String
  column url : String
  column role : Role
  column synced_at : Time?
  column metadata : Metadata
  column sync_failed_at : Time?

  scope :canonical do
    where(role: Role::Canonical)
  end

  scope :mirror do
    where(role: Role::Mirror)
  end

  def ref
    Ref.new(resolver, url)
  end
end
Clear.json_serializable_converter(Repo::Metadata)
require "shardbox-core/repo/ref"

@[Crinja::Attributes]
struct Repo::Ref
  include Crinja::Object::Auto
end

@[Crinja::Attributes]
class Release
  include Clear::Model
  include Crinja::Object::Auto

  record RevisionInfo, tag : Tag?, commit : Commit do
    include JSON::Serializable
  end

  record Commit, sha : String, time : Time, author : Signature, committer : Signature, message : String do
    include JSON::Serializable
  end

  record Tag, name : String, message : String, tagger : Signature do
    include JSON::Serializable
  end

  record Signature, name : String, email : String, time : Time do
    include JSON::Serializable
  end

  primary_key
  belongs_to shard : Shard
  has_many dependencies : Dependency
  has_many files : RepoFile

  column version : String
  column revision_info : RevisionInfo
  column spec : JSON::Any
  column position : Int32
  column latest : Bool?
  column released_at : Time
  column yanked_at : Time?

  column created_at : Time, presence: false
  column updated_at : Time, presence: false

  scope :latest do
    where(latest: true)
  end

  scope :ordered do
    order_by("position", :desc)
  end

  def revision_identifier
    if tag = revision_info.tag
      tag.name
    else
      revision_info.commit.sha
    end
  end

  def license : String?
    spec["license"]?.try &.as_s
  end

  def description : String?
    spec["description"]?.try &.as_s
  end

  def crystal : String?
    if crystal = spec["crystal"]?
      crystal.as_s? || crystal.as_f?.try &.to_s # A version might have been encoded as a number in YAML
    end
  end

  def yanked? : Bool
    !yanked_at.nil?
  end

  def file(path)
    files.find({path: path})
  end
end

Clear.json_serializable_converter(Release::RevisionInfo)

class RepoFile
  include Clear::Model

  self.table = "files"

  primary_key

  belongs_to release : Release
  column path : String
  column content : String?
end

@[Crinja::Attributes]
class Dependency
  include Clear::Model
  include Crinja::Object::Auto

  column name : String
  column spec : JSON::Any
  column scope : Scope

  belongs_to release : Release
  belongs_to repo : Repo

  column created_at : Time, presence: false
  column updated_at : Time, presence: false

  def shard
    repo.shard
  end

  scope :development do
    where(scope: Scope::Development)
  end

  scope :runtime do
    where(scope: Scope::Runtime)
  end
end


@[Crinja::Attributes]
struct Author
  include Crinja::Object::Auto
  getter name : String
  getter email : String?

  def initialize(@name : String)
    if name =~ /\A\s*(.+?)\s*<+(\s*.+?\s*)>/
      @name, @email = $1, $2
    else
      @name = name
    end
  end

  # This is a simple and not 100% valid regex for valid email addresses, but
  # for our purpose it should be fine.
  EMAIL_REGEX = /\A([\w+\-].?)+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i

  def valid_mail?
    @email.try(&.matches?(EMAIL_REGEX))
  end
end

@[Crinja::Attributes]
class Owner
  include Clear::Model
  include Crinja::Object::Auto

  primary_key
  column resolver : String
  column slug : String
  column name : String?
  column description : String?
  column extra : JSON::Any
  column shards_count : Int32?
  column dependents_count : Int32?
  column transitive_dependents_count : Int32?
  column dev_dependents_count : Int32?
  column transitive_dependencies_count : Int32?
  column dev_dependencies_count : Int32?
  column dependencies_count : Int32?
  column popularity : Float32?
  column created_at : Time, presence: false
  column updated_at : Time, presence: false

  has_many repos : Repo
  has_many shards : Shard, through: repos
end
