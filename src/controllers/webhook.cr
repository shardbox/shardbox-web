get "/webhook/import_catalog" do |context|
  secret = ENV["SHARDBOX_SECRET"]?
  unless secret
    halt context, status_code: HTTP::Status::NOT_FOUND.value
  end

  auth = context.request.headers["Authorization"]?
  unless auth
    context.response.headers["WWW-Authenticate"] = %[Basic realm="Webhook Authentication"]
    halt context, status_code: HTTP::Status::UNAUTHORIZED.value
  end

  unless auth == "Basic #{secret}"
    halt context, status_code: HTTP::Status::FORBIDDEN.value
  end

  Clear::SQL.execute("SELECT pg_notify('jobs', 'import_catalog')")
end
