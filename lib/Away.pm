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
    $tokens->{is_weekend} = \&is_weekend;
};

sub is_work_day {
    my @args = (@_ == 1) ? split(/-/, $_[0]) : @_;
    if (is_weekend(@args)) {
        return false;
    }
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

sub is_weekend {
    my ($y, $m, $d) = (@_ == 1) ? split(/-/, $_[0]) : @_;
    my $dt = DateTime->new(year => $y, month => $m, day => $d);
    if ($dt->day_of_week > 5) {
        return true;
    }
    return false;
}

get '/' => sub {
    my $dt = DateTime->now;
    redirect '/' . $dt->year . '/' . $dt->month;
};

my $year_re           = qr/\d{4}/;
my $months_as_numbers = join( '|', 1 .. 12 );
my $two_digit_months  = join( '|', map {sprintf("%02d", $_)} 1 .. 12 );
my $months_variations = join( '|', $months_as_numbers, $two_digit_months);
my $days_as_numbers   = join( '|', 1 .. 31, map(&pad2d, 1 .. 31) );

get '/availability' => sub {
    my $now = DateTime->now;
    redirect "/availability/" . $now->ymd('/');
};

get qr!/availability/($year_re)/($months_variations)! => sub {
    my ($y, $m) = splat;
    redirect "/availability/$y/$m/1" 
};

get qr!/availability/($year_re)/($months_variations)/($days_as_numbers)! => sub {
    my ( $year, $month, $day ) = splat;

    my $start_date = DateTime->new(
        year => $year, month => $month, day => $day);
    my $end_date = $start_date->clone->add( months => 1 );
    my $prior_date = $start_date->clone->subtract( months => 1 );

    my %leave_on_for_in;
    my %names = get_emp_names();

    for (my $i = $start_date->clone; $i < $end_date; $i->add(days => 1)) {
        $leave_on_for_in{$i->ymd} = {};
        my $leave = get_all_leave_on($i->ymd);
        while (my $res = $leave->next) {
            my $emp = $res->employee->name;
            my $am_pm = $res->is_pm ? "pm" : "am";
            $leave_on_for_in{$i->ymd}{$emp}{$am_pm} = $res->category;
        }
    }

    return template availability => {
        dt => $start_date,
        year => $year,
        month => $month,
        day => $day,
        leave_on_for_in => \%leave_on_for_in,
        names => \%names,
        this_week => $start_date->ymd('/'),
        one_week_back => $prior_date->ymd('/'),
        one_week_forward => $end_date->ymd('/'),
    };
};

sub get_emp_names {
    my $rs = schema('away')->resultset('Employee')->search(
        {
            # All
        },
        {
            "order_by" => {-asc => ['name']},
        },
    );
    return map {$_->name => $_->crsid} $rs->all;
}

# Takes either y-m-d or y, m, d
sub get_all_leave_on {
    my ($y, $m, $d) = (@_ == 1) ? split(/-/, $_[0]) : @_;
    my $rs = schema('away')->resultset('LeavePeriod')->search(
        {
            day => make_ymd_string($y, $m, $d),
        },
        {
            prefetch => 'employee',
        }
    );
    return $rs;
}

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
    my %allocated_periods;
    while (my $p = $rs->next) {
        my $key = $p->day . '-' . (($p->is_pm) ? "pm" : "am");
        $allocated_periods{$key} = $p;
    }

    return template month => {
        year      => $year,
        month     => sprintf("%02d", $month),
        monthname => $month_name,
        user      => $user,
        allocated => \%allocated_periods,
        view_name => 'month',
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
