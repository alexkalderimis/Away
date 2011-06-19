use strict;
use warnings;
use File::Basename qw/dirname/;
use Crypt::SaltedHash;
use lib dirname(__FILE__) . '/../lib';
use Away::DB;


my $script = __FILE__;

my $usage = <<"USAGE";

perl $script DB CRSID NAME HOLIDAY_ALLOWANCE [PASSWORD]

Add an employee to the database with the given crsid, name, and holiday allowance.
USAGE

(@ARGV == 5 || @ARGV == 4) or die "Expected 4 or 5 arguments: got " . scalar(@ARGV), $usage;

my ($file, $crsid, $name, $allowance, $secret) = @ARGV;

die "Cannot connect to $file - the file does not exist" unless (-f $file);

my $db = Away::DB->connect("dbi:SQLite:dbname=$file", undef, undef, {sqlite_unicode => 1}); 

$secret ||= generate_random_password(); 

my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
$csh->add($secret);

my $salted = $csh->generate;

my $emp = $db->resultset('Employee')->create({
            crsid => $crsid, 
            name => $name, 
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


