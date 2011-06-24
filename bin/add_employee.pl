use strict;
use warnings;
use Crypt::SaltedHash;
use Dancer ':syntax';
use Dancer::Config;
use Dancer::Plugin::DBIC qw(schema);
use Encode;

binmode STDIN, ':encoding(utf8)';
binmode STOUT, ':encoding(utf8)';

my $script = __FILE__;

my $usage = <<"USAGE";

perl $script ENVIRONMENT CRSID NAME HOLIDAY_ALLOWANCE [PASSWORD]

Add an employee to the database with the given crsid, name, and holiday allowance.
USAGE

(@ARGV == 5 || @ARGV == 4) or die "Expected 4 or 5 arguments: got " . scalar(@ARGV), $usage;

my ($environment, $crsid, $name, $allowance, $secret) = @ARGV;

set 'environment' => $environment;
set 'confdir' => dirname(__FILE__) . '/..';
Dancer::Config->load();

my $db = schema('away');

$secret ||= generate_random_password(); 

my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
$csh->add($secret);

my $salted = $csh->generate;

my $emp = $db->resultset('Employee')->create({
            crsid => decode_utf8($crsid), 
            name => decode_utf8($name), 
            holiday_allowance => $allowance,
            password_hash => $salted});

print "Added Employee: \n",
      "NAME:  ", $emp->name, "\n",
      "CRSID: ", $emp->crsid, "\n",
      "ALLOWANCE: ", $emp->holiday_allowance, "\n";

print "This user can log in with the password: $secret\n";

exit;

#### FUNCTIONS ####

sub generate_random_password {
    my $length_of_randomstring = 10;

    my @chars = ('a'..'z','A'..'Z','0'..'9', qw/_ ! £ $ % ^ & @ < > ?/);
    my $random_string;
    foreach (1..$length_of_randomstring) {
        # rand @chars will generate a random 
        # number between 0 and scalar @chars
        $random_string .= $chars[rand @chars];
    }
    return $random_string;
}


