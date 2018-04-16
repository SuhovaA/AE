use 5.016;
use warnings;
use lib './lib';

#use lib '/home/nastena/perl5/lib/perl5';
use LWP::UserAgent;
use HTTP::Request;


use Socket;

use AE::Simple;

use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Errno qw(EAGAIN EINTR EWOULDBLOCK);
sub logmsg { print "$0 $$: @_ at ", scalar localtime(), "\n" }

my $port  = 8888;
my $proto = getprotobyname("tcp");
socket(my $fd_server, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
setsockopt($fd_server, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) or die "setsockopt: $!";
bind($fd_server, sockaddr_in($port, INADDR_ANY)) or die "bind: $!";
listen($fd_server, SOMAXCONN) or  die "listen: $!";
logmsg "Server started on port $port";

my $flags = fcntl($fd_server, F_GETFL, 0) or die "Can't get flags for the socket: $!\n";
$flags = fcntl($fd_server, F_SETFL, $flags | O_NONBLOCK) or die "Can't set flags for the socket: $!\n";

my $obj = AE::Simple->new();

$obj->io($fd_server, "r", sub {

	my $paddr = accept(my $fd_client, $fd_server);
	my ($port, $iaddr) = sockaddr_in($paddr);
    my $name = gethostbyaddr($iaddr, AF_INET);
    logmsg "connection from $name [",inet_ntoa($iaddr), "] at port $port";
    autoflush $fd_client, 1;

	my $r;
	$r = $obj->io($fd_client, "r", sub {
		sysread($fd_client, my $buf, 1024);
		say $buf;
		$obj->destroy($r);
		my $w;
		my $ua = LWP::UserAgent->new();
		my $request = HTTP::Request->new(GET => 'https://cloud.mail.ru/public/5xLH/KvEHJdL1X');
		my $response = $ua->request($request);
		my $resp = $response->as_string;

		$w = $obj->io($fd_client, "w", sub {
			syswrite($fd_client, $resp);
			$obj->destroy($w);
		});
	})
});

$obj->io(\*STDIN, "r", sub {
	sysread(\*STDIN, my $buf, 1024);
	chomp($buf);
	if ($buf eq "exit") {
		exit 0;
	}
});

$obj->run_loop(1);
