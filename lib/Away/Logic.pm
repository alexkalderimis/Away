package Away::Logic;

use Dancer ':syntax';
use Exporter 'import';
use Date::Holidays::UK::EnglandAndWales qw/is_uk_holiday/;
use DateTime;

our @EXPORT = qw/
    is_work_day is_weekend parse_dt make_ymd_string
    /;

our @EXPORT_OK = (@EXPORT, qw/pad2d/);

sub make_ymd_string {
    my ( $y, $m, $d ) = @_;
    my $ymd = join( '-', map &pad2d, $y, $m, $d );
    return $ymd;
}

sub pad2d {
    return sprintf( "%02d", $_ );
}

sub parse_dt {
    my ( $y, $m, $d ) = ( @_ == 3 ) ? @_ : split( /-/, $_[0] );
    my $dt = DateTime->new( year => $y, month => $m, day => $d );
    return $dt;
}

sub is_weekend {
    my $dt = parse_dt(@_);
    if ( $dt->day_of_week > 5 ) {
        return true;
    }
    return false;
}

sub is_work_day {
    my @args = ( @_ == 1 ) ? split( /-/, $_[0] ) : @_;
    if ( is_weekend(@args) ) {
        return false;
    }
    if ( is_uk_holiday(@args) ) {
        return false;
    }
    for my $extra_hol ( @{ setting("extra_hols") } ) {
        if ( make_ymd_string(@$extra_hol) eq make_ymd_string(@args) ) {
            return false;
        }
    }
    return true;
}

true;
