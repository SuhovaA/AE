use 5.016;
use warnings;
use lib './lib';
use AE::Simple;
use AE::HTTP::Request;
use DDP;

my $method = 'get';
my $uri = '/webhp?hl=ru&sa=X&ved=0ahUKEwiuz8mW-sPaAhVI8ywKHQ06BhkQPAgD';
my %arg;
$arg{'headers'} = (Host => 'www.google.ru');
$arg{'body'} = "";
$arg{'cookie'} = (version => '1');

my $response = AE::HTTP::Request->new("www.google.ru", 80, $method, $uri, \%arg);

$response = AE::HTTP::Request->new("www.google.ru", 80, $method, $uri, \%arg);

p $response->{'status-line'};
p $response->{'headers'};
p $response->{'body'};
#p $response->{'cookie'};
p %arg;