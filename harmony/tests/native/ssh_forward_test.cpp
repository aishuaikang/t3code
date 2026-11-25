#include "ssh_session.h"
#include <cassert>
#include <iostream>
#include <poll.h>

static std::string incoming, written, forwarded_host;
static int forwarded_port = 0;
static bool remote_eof=false;
static int writes=0, freed=0, sessions_freed=0;
extern "C" ssize_t libssh2_channel_write_ex(LIBSSH2_CHANNEL*,int,const char* data,size_t size) {
  if (++writes==1) return LIBSSH2_ERROR_EAGAIN;
  size=std::min(size,size_t(2));written.append(data,size);return size;
}
extern "C" ssize_t libssh2_channel_read_ex(LIBSSH2_CHANNEL*,int,char* data,size_t size) {
  if(incoming.empty()) return LIBSSH2_ERROR_EAGAIN;
  size=std::min(size,incoming.size());memcpy(data,incoming.data(),size);incoming.erase(0,size);return size;
}
extern "C" int libssh2_channel_eof(LIBSSH2_CHANNEL*) {return remote_eof;}
extern "C" int libssh2_channel_send_eof(LIBSSH2_CHANNEL*) {return 0;}
extern "C" int libssh2_channel_free(LIBSSH2_CHANNEL*) {++freed;return 0;}
extern "C" int libssh2_keepalive_send(LIBSSH2_SESSION*,int*) {return 0;}
extern "C" void libssh2_session_set_blocking(LIBSSH2_SESSION*,int) {}
extern "C" void libssh2_session_set_timeout(LIBSSH2_SESSION*,long) {}
extern "C" int libssh2_session_free(LIBSSH2_SESSION*) {++sessions_freed;return 0;}
extern "C" int libssh2_session_last_errno(LIBSSH2_SESSION*) {return LIBSSH2_ERROR_EAGAIN;}
extern "C" LIBSSH2_CHANNEL* libssh2_channel_direct_tcpip_ex(LIBSSH2_SESSION*,const char* host,int port,const char*,int) {
  forwarded_host=host;forwarded_port=port;return nullptr;
}
int main() {
  int sockets[2];assert(socketpair(AF_UNIX,SOCK_STREAM,0,sockets)==0);
  t3ssh::Nonblocking(sockets[0]);t3ssh::Nonblocking(sockets[1]);
  t3ssh::Session session;
  session.session=reinterpret_cast<LIBSSH2_SESSION*>(1);session.running=true;
  session.clients.push_back({sockets[0],reinterpret_cast<LIBSSH2_CHANNEL*>(1),{}, {}});
  assert(send(sockets[1],"abcdef",6,0)==6);
  incoming="reply";
  session.Pump(); // First write would block; bytes must remain queued.
  assert(written.empty());
  for(int i=0;i<4;++i)session.Pump();
  assert(written=="abcdef");
  char result[16];auto count=recv(sockets[1],result,sizeof(result),0);
  assert(std::string(result,count)=="reply");
  // A conversation snapshot already buffered by SSH must not wait one worker tick per 16 KiB.
  int capacity=128*1024;
  assert(setsockopt(sockets[0],SOL_SOCKET,SO_SNDBUF,&capacity,sizeof(capacity))==0);
  assert(setsockopt(sockets[1],SOL_SOCKET,SO_RCVBUF,&capacity,sizeof(capacity))==0);
  const std::string snapshot(48 * 1024, 'x'); incoming=snapshot;
  session.Pump();
  auto drain = [&]() {
    std::string bytes; char chunk[8192]; ssize_t n;
    while ((n=recv(sockets[1],chunk,sizeof(chunk),0))>0) bytes.append(chunk,static_cast<size_t>(n));
    return bytes;
  };
  assert(drain()==snapshot);
  // Fill the local socket, then resume its reader. Retried writes must neither lose nor duplicate data.
  const std::string bulk(512*1024, 'y'); incoming=bulk;
  for (int i=0; i<8; ++i) session.Pump();
  std::string received=drain();assert(!received.empty() && received.size()<bulk.size());
  for (int i=0; i<64 && received.size()<bulk.size(); ++i) { session.Pump(); received+=drain(); }
  assert(received==bulk);
  shutdown(sockets[1],SHUT_WR);remote_eof=true;
  for(int i=0;i<3;++i)session.Pump();
  assert(session.clients.empty());assert(freed==1);
  // Closing an idle client must not wait for it to send data or EOF.
  close(sockets[1]);assert(socketpair(AF_UNIX,SOCK_STREAM,0,sockets)==0);
  session.clients.push_back({sockets[0],reinterpret_cast<LIBSSH2_CHANNEL*>(2),{}, {}});
  session.Close();assert(recv(sockets[1],result,sizeof(result),0)==0);
  assert(session.clients.empty());assert(sessions_freed==1);close(sockets[1]);
  assert(!session.Pump());
  // The SSH peer resolves the service address. An EAGAIN retry must keep that destination.
  session.running=true;session.session=reinterpret_cast<LIBSSH2_SESSION*>(1);
  const auto id=session.OpenForward("t3.internal",0,3773);
  sockaddr_in bound{};socklen_t size=sizeof(bound);
  assert(getsockname(session.forwards.at(id).listen_fd,reinterpret_cast<sockaddr*>(&bound),&size)==0);
  assert(ntohl(bound.sin_addr.s_addr)==INADDR_LOOPBACK);
  int local=socket(AF_INET,SOCK_STREAM,0);assert(local>=0);
  assert(connect(local,reinterpret_cast<sockaddr*>(&bound),size)==0);
  pollfd listener{session.forwards.at(id).listen_fd,POLLIN,0};assert(poll(&listener,1,1000)==1 && (listener.revents&POLLIN));
  for(int i=0;i<2;++i){forwarded_host.clear();session.Pump();assert(forwarded_host=="t3.internal" && forwarded_port==3773);}
  close(local);session.Close();
  std::cout<<"partial SSH writes, backpressure, bidirectional bytes, EOF and idle close pass\n";
}
