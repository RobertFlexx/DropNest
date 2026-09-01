@external(erlang, "dropnest_ffi", "hmac_sha256")
pub fn hmac_sha256(key: String, value: String) -> String

@external(erlang, "dropnest_ffi", "secure_equals")
pub fn secure_equals(left: String, right: String) -> Bool

@external(erlang, "dropnest_ffi", "claim_invite")
pub fn claim_invite(invite: String, device: String, limit: Int) -> Bool

@external(erlang, "dropnest_ffi", "rate_limit")
pub fn rate_limit(key: String, limit: Int, window_seconds: Int) -> Bool

@external(erlang, "dropnest_ffi", "init_security_state")
pub fn setup() -> Nil

@external(erlang, "dropnest_ffi", "prune_rate_limits")
pub fn prune_rate_limits(max_age_seconds: Int) -> Nil
