use 5.016;
use warnings;
use lib './lib';
use AE::Simple;
use AE::HTTP::Request;
use DDP;

my $method = 'GET';
my $uri = '/';
my %arg;
$arg{'headers'} = {host => 'www.perlmonks.org'};
$arg{'body'} = '';
$arg{'cookie'} = {version => '1'};

my $response = AE::HTTP::Request->new('www.perlmonks.org', 80, $method, $uri, \%arg);

#$response = AE::HTTP::Request->new("www.google.ru", 80, $method, $uri, \%arg);
p $response->{'status-line'};
p $response->{'headers'};
p $response->{'body'};
#p $response->{'cookie'};
p %arg;
