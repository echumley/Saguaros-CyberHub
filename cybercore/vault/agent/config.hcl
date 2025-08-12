exit_after_auth = false
pid_file = "/tmp/vault-agent.pid"

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path                   = "/agent/role_id"
      secret_id_file_path                 = "/agent/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }
  sink "file" {
    config = { path = "/tmp/.vault-token" }
  }
}

template {
  source      = "/agent/templates/pgpass.ctmpl"
  destination = "/secrets/pgpass"
  perms       = "0600"
}