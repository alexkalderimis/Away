package Away::DB::Functions;

use Dancer ':syntax';
use Dancer::Plugin::DBIC qw(schema);
use DateTime;
use List::MoreUtils qw/uniq/;

use Away::Logic qw/make_ymd_string parse_dt/;

use Exporter 'import';

use constant BUSINESS => "Meeting/Seminar/Conference";

our @EXPORT_OK = qw/
    Employee LeavePeriod get_emp_names get_all_leave_on BUSINESS
    get_all_leave_on get_leave_years get_available_leave
    /;

our @EXPORT = qw/
    Employee LeavePeriod get_emp_names get_all_leave_on BUSINESS
    get_all_leave_on get_leave_years get_available_leave
    /;

sub Employee() {
    return schema('away')->resultset('Employee');
}

sub LeavePeriod() {
    return schema('away')->resultset('LeavePeriod');
}

sub get_emp_names {
    my $rs = Employee->search(
        {

            # All
        },
        { "order_by" => { -asc => ['name'] }, },
    );
    return map { $_->name => $_->crsid } $rs->all;
}

# Takes either y-m-d or y, m, d
sub get_all_leave_on {
    my ( $y, $m, $d ) = ( @_ == 1 ) ? split( /-/, $_[0] ) : @_;
    my $rs = LeavePeriod->search( 
        { day      => make_ymd_string( $y, $m, $d ), },
        { prefetch => 'employee', }
    );
    return $rs;
}

sub get_leave_years {
    my $user = shift;
    my @years =
      uniq( sort( map { parse_dt( $_->day )->year } $user->leave_periods ) );
    return @years;
}

sub get_available_leave {
    my $user = shift;
    my ( $y, $m, $d ) = @_;
    my $now = ( @_ == 3 )
              ? DateTime->new( year => $y, month => $m, day => $d )
              : DateTime->now;

    my ( $nym, $nyd ) = @{ Dancer::setting("year_begins") };
    my $ny = DateTime->new( year => $now->year, month => $nym, day => $nyd );
    my ( $start, $end );
    if ( $now < $ny ) {
        $end = $ny;
        $start =
          DateTime->new( year => $now->year - 1, month => $nym, day => $nyd );
    } else {
        $start = $ny;
        $end =
          DateTime->new( year => $now->year + 1, month => $nym, day => $nyd );
    }

    my $rs = $user->search_related(
        'leave_periods',
        {
            -and => [
                category => { '!=' => BUSINESS },
                day      => { '>=' => $start->ymd },
                day      => { '<'  => $end->ymd },
            ],
        }
    );
    return $user->holiday_allowance - ( $rs->count / 2 );
}

true;
