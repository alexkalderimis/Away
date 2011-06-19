create table leave_period (
    id integer not null primary key,
    requested_on date not null default (date('now')),
    note text not null default 'holiday',
    category text not null default 'holiday',
    day date not null,
    is_pm boolean not null,
    employee integer references employee(id)
);

create table employee (
    id integer not null primary key,
    crsid text not null unique,
    name text not null,
    password_hash text not null,
    holiday_allowance integer not null default 0
);

