use 5.016;
use warnings;
use lib './lib';
use AE::Simple;
use AE::HTTP_request;
use DDP;

my $method = 'get';
my $uri = '"https://www.google.com"';
my %arg;
$arg{'headers'} = {};
$arg{'body'} = "";
my $response = AE::HTTP_request->new("localhost", "8888", $method, $uri, %arg);

p $response->{'status-line'};
p $response->{'headers'};
p $response->{'body'};
