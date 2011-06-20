package Away;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::ProxyPath;
use Dancer::Plugin::DBIC qw(schema);

use Date::Holidays::UK::EnglandAndWales qw/is_uk_holiday/;
use DateTime;
use List::MoreUtils qw/uniq/;

our $VERSION = '0.1';

use constant BUSINESS => "Meeting/Seminar/Conference";

before_template sub {
    my $tokens = shift;
    $tokens->{is_work_day} = \&is_work_day;
};

sub is_work_day {
    my @args = @_;
    if (is_uk_holiday(@args)) {
        return false;
    }
    for my $extra_hol (@{ setting("extra_hols") }) {
        if (make_ymd_string(@$extra_hol) eq make_ymd_string(@args)) {
            return false;
        }
    }
    return true;
}

get '/' => sub {
    my $dt = DateTime->now;
    redirect '/' . $dt->year . '/' . $dt->month;
};

my $year_re           = qr/\d{4}/;
my $months_as_numbers = join( '|', 1 .. 12 );
my $two_digit_months  = join( '|', map {sprintf("%02d", $_)} 1 .. 12 );
my $days_as_numbers   = join( '|', 1 .. 31 );

my $month_handler = sub {

    my ( $year, $month, $day ) = splat;
    my $cal = DateTime->new(
        month => $month,
        year  => $year
    );

    my $month_name = $cal->month_name;
    my $user =
      schema('away')->resultset('Employee')
      ->find( { crsid => request->user() } );
    unless ($user) {
        status(404);
        return "Not found";    # Should never happen.
    }

    my $start = join('-', map {sprintf("%02d", $_)} $year, $month, 1);
    my $end = join('-', map {sprintf("%02d", $_)} $year, $month, 31);

    my $rs = $user->search_related(
         'leave_periods',
         {
             day => { '>=' => $start }
         }
       )->search(
         {
             day => { '<=' => $end }
         }
       );
    debug(to_dumper({query => $rs->as_query, count => $rs->count}));

    return template month => {
        year      => $year,
        month     => sprintf("%02d", $month),
        monthname => $month_name,
        user      => $user,
        allocated => $rs,
    };
};

get qr!/($year_re)/($months_as_numbers)! => $month_handler; 
get qr!/($year_re)/($two_digit_months)! => $month_handler; 

get '/profile' => sub {
    my $user = schema('away')->resultset('Employee')
                             ->find({crsid => request->user()});
    unless ($user) {
        status(404);
        return "Not found";    # Should never happen.
    }

    my @half_days_off = $user->search_related(
        'leave_periods',
        {
            # ALL
        },
        {
            order_by => {-asc => ['day', 'note']},
        }
    );

    return template user => {
        user          => $user,
        half_days_off => \@half_days_off,
        leave_calculator => \&get_available_leave,
        get_leave_years => \&get_leave_years,
    };
};

sub _parse_date {
    my $date = shift;
    my ($y, $m, $d) = split(/-/, $date);
    my $dt = DateTime->new(year => $y, month => $m, day => $d);
    return $dt;
}

sub get_leave_years {
    my $user = shift;
    my @years = uniq(sort(map {_parse_date($_->day)->year} $user->leave_periods));
    return @years;
}

sub get_available_leave {
    my $user = shift;
    my ($y, $m, $d) = @_;
    my $now = (@_ == 3) 
        ? DateTime->new(year => $y, month => $m, day => $d)
        : DateTime->now;

    my $allocation = $user->holiday_allowance;
    my ($nym, $nyd) = @{ setting("year_begins") };
    my $ny = DateTime->new(year => $now->year, month => $nym, day => $nyd);
    my ($start, $end);
    if ($now < $ny) {
        $end = $ny;
        $start = DateTime->new(
            year => $now->year - 1, month => $nym, day => $nyd);
    } else {
        $start = $ny;
        $end =  DateTime->new(
            year => $now->year + 1, month => $nym, day => $nyd);
    }

    my $rs = $user->search_related('leave_periods', {
            category => {'!=' => BUSINESS},
        })->search({
            day => {'>=', $start->ymd},
        })->search({
            day => {'<', $end->ymd},
        });
    debug($rs->as_query);
    return $allocation - ($rs->count / 2);
}

post '/add_period' => sub {
    my $crsid     = param "user";
    my $half_days = param "half_days";
    my $note      = param "note";
    my $category  = param "category";
    my @periods =
      ( ref $half_days eq 'ARRAY' )
      ? @$half_days
      : ($half_days);

    my $user =
      schema('away')->resultset('Employee')->find( { crsid => $crsid } );
    status(404) and return "Not found" unless $user;

    my @added;

    for my $period (@periods) {
        my ( $y, $m, $d, $am_pm ) = split( /-/, $period );
        my $day = join('-', map {sprintf("%02d", $_)} $y, $m, $d);
        # First clear out existing ones.
        $user->search_related('leave_periods', { 
                day => $day, 
                is_pm => ( $am_pm eq 'pm' ) ? 1 : 0,
            })->delete();

        if ($category ne "REMOVE") {
            if ($category eq BUSINESS 
                    or get_available_leave($user, $y, $m, $d) > 0) {
                push @added, $period;
                $user->add_to_leave_periods(
                    {
                        day      => $day,
                        note     => $note,
                        category => $category,
                        is_pm => ( $am_pm eq 'pm' ) ? 1 : 0,
                    }
                );
            }
        }
    }

    my @ids = ($category eq 'REMOVE') ? @periods : @added;

    return to_json(
        {
            ids      => [@ids],
            note     => $note,
            category => $category,
            all_added => (@ids == @periods) ? \1 : \0,
        }
    );
};

sub make_ymd_string {
    my ($y, $m, $d) = @_;
    my $ymd = join('-', map &pad2d, $y, $m, $d);
    return $ymd;
}

sub pad2d  {
    return sprintf("%02d", $_);
}

post '/cancel_leave' => sub {
    my $crsid = param "crsid";
    my $periods = param "leave_periods";

    my @periods = (ref $periods eq 'ARRAY') ? @$periods : ($periods);

    my $user =
      schema('away')->resultset('Employee')->find( { crsid => $crsid } );
    status(404) and return "Not found" unless $user;
    
    my $deleted_count = 0;
    for my $p (@periods) {
        my ($start_id, $end_id) = split(/-/, $p);
        my $first = $user->find_related('leave_periods', { id => $start_id });
        next unless $first;

        my $last = $user->find_related('leave_periods', { id => $end_id });
        next unless $last;

        my ($cat, $note) = ($first->category, $first->note);

        my $candidates = $user->search_related('leave_periods', 
            {
                day => {'>=' => $first->day},
                category => $first->category,
                note => $first->note,
            },
            { 
                order_by => {'-asc' => ['day']}
            }
        )->search({day => {'<=' => $last->day}});

        debug($candidates->count . " candidates");
        $deleted_count += $candidates->count;
        $candidates->delete();
    }
    return to_json({deleted_count => $deleted_count});
};

true;
