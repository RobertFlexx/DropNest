@external(erlang, "dropnest_ffi", "hmac_sha256")
pub fn hmac_sha256(key: String, value: String) -> String

@external(erlang, "dropnest_ffi", "secure_equals")
pub fn secure_equals(left: String, right: String) -> Bool

@external(erlang, "dropnest_ffi", "claim_invite")
pub fn claim_invite(invite: String, device: String, limit: Int) -> Bool

pub type InviteClaim {
  InviteAccepted
  InviteUnavailable
  InviteExpired
  InviteInvalid
  InviteFull
}

@external(erlang, "dropnest_ffi", "set_active_invite")
pub fn set_active_invite(token: String, digest: String, expires_at: Int) -> Nil

@external(erlang, "dropnest_ffi", "clear_active_invite")
pub fn clear_active_invite() -> Nil

@external(erlang, "dropnest_ffi", "get_active_invite")
pub fn active_invite() -> Result(#(String, String, Int), Nil)

@external(erlang, "dropnest_ffi", "claim_active_invite")
fn claim_active_invite_code(
  supplied_digest: String,
  device: String,
  now: Int,
  limit: Int,
) -> Int

pub fn claim_active_invite(
  supplied_digest: String,
  device: String,
  now: Int,
  limit: Int,
) -> InviteClaim {
  case claim_active_invite_code(supplied_digest, device, now, limit) {
    1 -> InviteAccepted
    2 -> InviteExpired
    3 -> InviteInvalid
    4 -> InviteFull
    _ -> InviteUnavailable
  }
}

@external(erlang, "dropnest_ffi", "rate_limit")
pub fn rate_limit(key: String, limit: Int, window_seconds: Int) -> Bool

@external(erlang, "dropnest_ffi", "init_security_state")
pub fn setup() -> Nil

@external(erlang, "dropnest_ffi", "prune_rate_limits")
pub fn prune_rate_limits(max_age_seconds: Int) -> Nil
