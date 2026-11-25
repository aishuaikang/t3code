#include "ssh_host_key.h"
#include <cassert>
#include <iostream>

static unsigned char digest[32];
static bool has_hash = true;
static int auth_calls = 0;
static int auth_result = 0;
extern "C" const char* libssh2_hostkey_hash(LIBSSH2_SESSION*, int type) {
  assert(type == LIBSSH2_HOSTKEY_HASH_SHA256);
  return has_hash ? reinterpret_cast<const char*>(digest) : nullptr;
}
extern "C" int libssh2_userauth_password_ex(LIBSSH2_SESSION*, const char*, unsigned int,
  const char*, unsigned int, void (*)(LIBSSH2_SESSION*, char**, int*, void**)) {
  ++auth_calls;
  return auth_result;
}
int main() {
  for (int i = 0; i < 32; ++i) digest[i] = static_cast<unsigned char>(i);
  const std::string pin = "SHA256:AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8";
  assert(t3ssh::Fingerprint(digest) == pin);
  assert(t3ssh::AuthenticatePinned(nullptr, "user", "password", "") != nullptr);
  assert(auth_calls == 0);
  assert(t3ssh::AuthenticatePinned(nullptr, "user", "password", pin + "=") != nullptr);
  assert(auth_calls == 0);
  std::string wrong = pin; wrong.back() = 'A';
  assert(t3ssh::AuthenticatePinned(nullptr, "user", "password", wrong) != nullptr);
  assert(auth_calls == 0);
  has_hash = false;
  assert(t3ssh::AuthenticatePinned(nullptr, "user", "password", pin) != nullptr);
  assert(auth_calls == 0);
  has_hash = true;
  assert(t3ssh::AuthenticatePinned(nullptr, "user", "password", pin) == nullptr);
  assert(auth_calls == 1);
  auth_result = LIBSSH2_ERROR_AUTHENTICATION_FAILED;
  assert(std::string(t3ssh::AuthenticatePinned(nullptr, "user", "password", pin)) == "SSH authentication failed");
  assert(auth_calls == 2);
  for (int code : {LIBSSH2_ERROR_TIMEOUT, LIBSSH2_ERROR_SOCKET_TIMEOUT, LIBSSH2_ERROR_SOCKET_SEND,
                   LIBSSH2_ERROR_SOCKET_RECV, LIBSSH2_ERROR_SOCKET_DISCONNECT}) {
    auth_result = code;
    assert(std::string(t3ssh::AuthenticatePinned(nullptr, "user", "password", pin)) == "SSH socket error during sign-in");
  }
  std::cout << "host key checked before authentication; missing/mismatched keys rejected\n";
}
