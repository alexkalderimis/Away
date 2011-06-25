package Away;

use strict;
use warnings;

use Away::DB::Functions;
use Away::Logic;

use Dancer ':syntax';
use Dancer::Plugin::ProxyPath;

use DateTime;

our $VERSION = '0.1';

my $months_as_numbers = join( '|', 1 .. 12, map( &Away::Logic::pad2d, 1 .. 12 ) );
my $days_as_numbers   = join( '|', 1 .. 31, map( &Away::Logic::pad2d, 1 .. 31 ) );

my $year_re           = qr/\d{4}/;
my $months_re         = qr/$months_as_numbers/;
my $days_re           = qr/$days_as_numbers/;

before_template sub {
    my $tokens = shift;
    $tokens->{now}         = DateTime->now;
    $tokens->{is_work_day} = \&Away::Logic::is_work_day;
    $tokens->{is_weekend}  = \&Away::Logic::is_weekend;
    $tokens->{datetime}    = \&Away::Logic::parse_dt;
};

#### ROUTE DEFINITIONS ####

get '/' => sub {
    my $dt = DateTime->now;
    redirect '/' . $dt->year . '/' . $dt->month;
};

get '/availability' => sub {
    redirect "/availability/" . DateTime->now->ymd('/');
};

get qr!/availability/($year_re)/($months_re)! => sub {
    my ( $y, $m ) = splat;
    redirect "/availability/$y/$m/1";
};

get qr!/availability/($year_re)/($months_re)/($days_re)! => \&handleAvailibility;

get qr!/availability/($year_re)/($months_re)/($days_re).table! => sub {
    handleAvailibility(true);
};

sub handleAvailibility {
    my $only_table = shift;
    my ( $year, $month, $day ) = splat;

    my $start_date = parse_dt($year, $month, $day);
    my $end_date = $start_date->clone->add( months => 1 );
    my $prior_date = $start_date->clone->subtract( months => 1 );

    my %leave_on_for_in;
    my %names = get_emp_names();

    for ( my $i = $start_date->clone ; $i < $end_date ; $i->add( days => 1 ) ) {
        $leave_on_for_in{ $i->ymd } = {};
        my $leave = get_all_leave_on( $i->ymd );
        while ( my $res = $leave->next ) {
            my $emp = $res->employee->name;
            my $am_pm = $res->is_pm ? "pm" : "am";
            $leave_on_for_in{ $i->ymd }{$emp}{$am_pm} = $res->category;
        }
    }

    my $opts = ($only_table) ? {layout => undef} : {};
    my $template = ($only_table) ? "availability_table" : "availability";

    return template $template => {
        dt               => $start_date,
        year             => $year,
        month            => $month,
        day              => $day,
        leave_on_for_in  => \%leave_on_for_in,
        names            => \%names,
        this_week        => $start_date->ymd('/'),
        one_week_back    => $prior_date->ymd('/'),
        one_week_forward => $end_date->ymd('/'),
        view_name        => 'availability',
    }, $opts;
};

get qr!/($year_re)/($months_re)(?:/0?1)?! => \&handleMonthDisplay;
get qr!/($year_re)/($months_re)(?:/0?1)?.table! => sub {
    return handleMonthDisplay(true);
};

sub handleMonthDisplay {
    my $only_table = shift;
    my ( $year, $month ) = splat;
    my $dt = DateTime->new(
        month => $month,
        year  => $year,
        day   => 1,
    );

    my $month_name = $dt->month_name;
    my $user = Employee->find( { crsid => request->user() } );
    unless ($user) {
        status(404);
        return "Not found";    # Should never happen.
    }

    my $start = $dt->strftime('%F');
    my $end   = $dt->clone->add(months => 1)->strftime('%F');

    my $rs = $user->search_related( 'leave_periods', 
        { -and => [ 
            day => { '>=' => $start }, 
            day => { '<'  => $end } 
        ]}
    );
    my %allocated_periods;
    while ( my $p = $rs->next ) {
        my $key = $p->day . '-' . (( $p->is_pm ) ? "pm" : "am" );
        $allocated_periods{$key} = $p;
    }

    my $opts = ($only_table) ? {layout => undef} : {};
    my $template = ($only_table) ? "month_table" : "month";

    return template $template => {
        year      => $year,
        month     => sprintf( "%02d", $month ),
        monthname => $month_name,
        user      => $user,
        allocated => \%allocated_periods,
        view_name => 'month',
    }, $opts;
};

get '/profile' => sub {
    my $user = Employee->find( { crsid => request->user() } );
    unless ($user) {
        status(404);
        return "Not found";    # Should never happen.
    }

    my @half_days_off = $user->search_related(
        'leave_periods',
        {

            # ALL
        },
        { order_by => { -asc => [ 'day', 'note' ] }, }
    );

    return template user => {
        user             => $user,
        half_days_off    => \@half_days_off,
        leave_calculator => \&get_available_leave,
        get_leave_years  => \&get_leave_years,
    };
};

post '/add_period' => sub {
    my $crsid     = param "user";
    my $half_days = param "half_days";
    my $note      = param "note";
    my $category  = param "category";
    my @periods =
      ( ref $half_days eq 'ARRAY' )
      ? @$half_days
      : ($half_days);

    my $user = Employee->find( { crsid => $crsid } );
    status(404) and return "Not found" unless $user;

    my (@added, @deleted_ids);

    for my $period (@periods) {
        my ( $y, $m, $d, $am_pm ) = split( /-/, $period );
        my $day = join( '-', map { sprintf( "%02d", $_ ) } $y, $m, $d );

        # First clear out existing ones.
        my @constraints = (day   => $day, is_pm => ( $am_pm eq 'pm' ) ? 1 : 0,);
        push @constraints, day => { '>=' => DateTime->now->strftime('%F') }
            if ($category eq "REMOVE");

        my $delenda = $user->search_related('leave_periods', { -and => \@constraints });
        push @deleted_ids, map {$_->day . '-' . (($_->is_pm) ? "pm" : "am")} $delenda->all;
        $delenda->delete();

        if ( $category ne "REMOVE" ) {
            if ( $category eq BUSINESS
                or get_available_leave( $user, $y, $m, $d ) > 0 )
            {
                push @added, $period;
                $user->add_to_leave_periods(
                    {
                        day      => $day,
                        note     => $note,
                        category => $category,
                        is_pm    => ( $am_pm eq 'pm' ) ? 1 : 0,
                    }
                );
            }
        }
    }

    my @ids = ( $category eq 'REMOVE' ) ? @deleted_ids : @added;

    return to_json(
        {
            ids       => [@ids],
            note      => $note,
            category  => $category,
            all_added => ( @ids == @periods ) ? \1 : \0,
        }
    );
};

post '/cancel_leave' => sub {
    my $crsid   = param "crsid";
    my $periods = param "leave_periods";

    my @periods = ( ref $periods eq 'ARRAY' ) ? @$periods : ($periods);

    my $user = Employee->find( { crsid => $crsid } );
    status(404) and return "Not found" unless $user;

    my $deleted_count = 0;
    for my $p (@periods) {
        my ( $start_id, $end_id ) = split( /-/, $p );
        my $first = $user->find_related( 'leave_periods', { id => $start_id } );
        next unless $first;

        my $last = $user->find_related( 'leave_periods', { id => $end_id } );
        next unless $last;

        my ( $cat, $note ) = ( $first->category, $first->note );

        my $candidates = $user->search_related(
            'leave_periods',
            {
                -and => [
                    day      => { '>=' => $first->day },
                    day      => { '<=' => $last->day },
                    day      => { '>=' => DateTime->now->strftime('%F') },
                    category => $first->category,
                    note     => $first->note,
                ],
            },
            { order_by => { '-asc' => ['day'] } }
        );

        $deleted_count += $candidates->count;
        $candidates->delete();
    }
    return to_json( { deleted_count => $deleted_count } );
};

get '/get_new_hrefs' => sub {
    my $currentHref = param "currentHref";
    my @parts = split('/', $currentHref);

    my $dt = eval { parse_dt(@parts[-3, -2, -1]) } || parse_dt(@parts[-2, -1], 1);

    my $fragment = ($currentHref =~ /availability/) ? '/availability/' : '/';

    my $ret = {
        monthName => $dt->month_name,
        year => $dt->year,
        backLink => "" . proxy->uri_for($fragment . $dt->clone->subtract(months => 1)->ymd('/')),
        fwdLink => "" . proxy->uri_for($fragment . $dt->clone->add(months => 1)->ymd('/')),
    };
    return to_json($ret);
};

get '/update_user_name' => sub {
    my $new_name = param "newName";
    my $crsid = request->user();

    my $user = Employee->find( { crsid => $crsid } );
    status(404) and return "Not found" unless $user;

    $user->update({ name => $new_name });

    return to_json({newName => $new_name});
};

true;
